#!/usr/bin/env ruby
# encoding: utf-8

$:.unshift("lib/")

require "test/unit"
require "mp3info"
require "fileutils"
require "tempfile"
require "zlib"
require "yaml"

GOT_ID3V2 = system("which id3v2 > /dev/null")

class Mp3InfoTest < Test::Unit::TestCase

  TEMP_FILE = File.join(File.dirname(__FILE__), "test_mp3info.mp3")

  DUMMY_TAG2 = {
    "COMM" => "comments",
    #"TCON" => "genre_s" 
    "TIT2" => "title",
    "TPE1" => "artist",
    "TALB" => "album",
    "TYER" => "year",
    "TRCK" => "tracknum"
  }

  DUMMY_TAG1 = {
    "title"    => "toto",
    "artist"   => "artist 123", 
    "album"    => "ALBUMM",
    "year"     => 1934,
    "tracknum" => 14,
    "comments" => "comment me",
    "genre" => 233
  }

  def setup
    @tag = {
      "title" => "title",
      "artist" => "artist",
      "album" => "album",
      "year" => 1921,
      "comments" => "comments",
      "genre" => 0,
      "genre_s" => "Blues",
      "tracknum" => 36
    }
    load_fixture_to_temp_file("empty_mp3")
  end

  def teardown
    FileUtils.rm_f(TEMP_FILE)
  end

  def test_to_s
    Mp3Info.open(TEMP_FILE) { |info| assert(info.to_s.is_a?(String)) }
  end

  def test_not_an_mp3
    File.open(TEMP_FILE, "w") do |f|
      str = "0"*1024*1024
      f.write(str)
    end
    assert_raises(Mp3InfoError) do
      mp3 = Mp3Info.new(TEMP_FILE)
    end
  end

  def test_is_an_mp3
    assert_nothing_raised do
      Mp3Info.new(TEMP_FILE).close
    end
  end
  
  def test_detected_info
    Mp3Info.open(TEMP_FILE) do |mp3|
      assert_mp3_info_are_ok(mp3)
    end
  end
  
  def test_vbr_mp3_length
    load_fixture_to_temp_file("vbr")

    Mp3Info.open(TEMP_FILE) do |info|
      assert(info.vbr)
      assert_in_delta(174.210612, info.length, 0.000001)
    end
  end

  def test_removetag1
    Mp3Info.open(TEMP_FILE) { |info| info.tag1 = @tag }
    assert(Mp3Info.hastag1?(TEMP_FILE))
    Mp3Info.removetag1(TEMP_FILE)
    assert(! Mp3Info.hastag1?(TEMP_FILE))
  end

  def test_writetag1
    Mp3Info.open(TEMP_FILE) { |info| info.tag1 = @tag }
    Mp3Info.open(TEMP_FILE) { |info| assert_equal(info.tag1, @tag) }
  end

  def test_valid_tag1_1
    tag = [ "title", "artist", "album", "1921", "comments", 36, 0].pack('A30A30A30A4a29CC')
    valid_tag = {
      "title" => "title",
      "artist" => "artist",
      "album" => "album",
      "year" => 1921,
      "comments" => "comments",
      "genre" => "Blues",
      #"version" => "1",
      "tracknum" => 36
    }
    id3_test(tag, valid_tag)
  end
  
  def test_valid_tag1_0
    tag = [ "title", "artist", "album", "1921", "comments", 0].pack('A30A30A30A4A30C')
    valid_tag = {
      "title" => "title",
      "artist" => "artist",
      "album" => "album",
      "year" => 1921,
      "comments" => "comments",
      "genre" => "Blues",
      #"version" => "0"
    }
    id3_test(tag, valid_tag)
  end

  def id3_test(tag_str, valid_tag)
    tag = "TAG" + tag_str
    File.open(TEMP_FILE, "a") do |f|
      f.write(tag)
    end
    assert(Mp3Info.hastag1?(TEMP_FILE))
    #info = Mp3Info.new(TEMP_FILE)
    #FIXME validate this test
    #assert_equal(info.tag1, valid_tag)
  end

  def test_removetag2
    w = write_tag2_to_temp_file("TIT2" => "sdfqdsf")

    assert( Mp3Info.hastag2?(TEMP_FILE) )
    Mp3Info.removetag2(TEMP_FILE)
    assert( ! Mp3Info.hastag2?(TEMP_FILE) )
  end


  # when frame is not present to begin with, setting it to nil or empty is not a change
  def test_tag2_changed?
    w = write_tag2_to_temp_file("TIT2" => "")
    Mp3Info.open(TEMP_FILE) do |mp3|
      mp3.tag2.TIT2 = ""
      refute(mp3.tag2.changed?)
      mp3.tag2.TIT2 = nil
      refute(mp3.tag2.changed?)
      mp3.tag2.TIT2 = "foo"
      assert(mp3.tag2.changed?)
      mp3.tag2.TIT2 = 'bar'
      assert(mp3.tag2.changed?)
    end
  end

  def test_hastags
    Mp3Info.open(TEMP_FILE) do |info| 
      info.tag1 = @tag
    end
    assert(Mp3Info.hastag1?(TEMP_FILE))

    written_tag = write_tag2_to_temp_file(DUMMY_TAG2)
    assert(Mp3Info.hastag2?(TEMP_FILE))
  end

  def test_universal_tag
    2.times do 
      tag = {"title" => "title"}
      Mp3Info.open(TEMP_FILE) do |mp3|
	tag.each { |k,v| mp3.tag[k] = v }
      end
      w = Mp3Info.open(TEMP_FILE) { |m| m.tag }
      assert_equal(tag, w)
    end
  end

  def test_id3v2_universal_tag
    tag = {}
    %w{comments title artist album}.each { |k| tag[k] = k }
    tag["tracknum"] = 34
    Mp3Info.open(TEMP_FILE) do |mp3|
      tag.each { |k,v| mp3.tag[k] = v }
    end
    w = Mp3Info.open(TEMP_FILE) { |m| m.tag }
    w.delete("genre")
    w.delete("genre_s")
    assert_equal(tag, w)
#    id3v2_prog_test(tag, w)
  end

  def test_id3v2_version
    written_tag = write_tag2_to_temp_file(DUMMY_TAG2)
    assert_equal( "2.3.0", written_tag.version )
  end

  def test_id3v2_methods
    tag = { "TIT2" => "tit2", "TPE1" => "tpe1" }
    Mp3Info.open(TEMP_FILE) do |mp3|
      tag.each do |k, v|
        mp3.tag2.send("#{k}=".to_sym, v)
      end
      assert_equal(tag, mp3.tag2)
    end
  end

  def test_id3v2_basic
    written_tag = write_tag2_to_temp_file(DUMMY_TAG2)
    assert_equal(DUMMY_TAG2, written_tag)
    id3v2_prog_test(DUMMY_TAG2, written_tag)
  end

  #test the tag with the "id3v2" program
  def id3v2_prog_test(tag, written_tag)
    return unless GOT_ID3V2
    start = false
    id3v2_output = {}
=begin
    id3v2 tag info for test/test_mp3info.mp3:
      COMM (Comments): (~)[ENG]: 
      test/test_mp3info.mp3: No ID3v1 tag
=end
    raw_output = `id3v2 -l #{TEMP_FILE}`
    raw_output.split(/\n/).each do |line|
      if line =~ /^id3v2 tag info/
        start = true 
	next    
      end
      next unless start
      if match = /^(.{4}) \(.+\): (.+)$/.match(line)
        k, v = match[1, 2]
        case k
          #COMM (Comments): ()[spa]: fmg
          when "COMM"
            v.sub!(/\(\)\[.{3}\]: (.+)/, '\1')
        end
        id3v2_output[k] = v
      end
    end

    assert_equal( id3v2_output, written_tag, "id3v2 program output doesn't match")
  end

  def test_id3v2_complex
    tag = {}
    #ID3v2::TAGS.keys.each do |k|
    ["PRIV", "APIC"].each do |k|
      tag[k] = random_string(50)
    end

    got_tag = write_tag2_to_temp_file(tag)
    assert_equal(tag, got_tag)
  end

  def test_id3v2_bigtag
    tag = {"APIC" => random_string(1024) }
    assert_equal(tag, write_tag2_to_temp_file(tag))
  end

  def test_leading_char_gets_chopped
    tag2 = DUMMY_TAG2.dup
    tag2["WOAR"] = "http://foo.bar"
    w = write_tag2_to_temp_file(tag2)
    assert_equal("http://foo.bar", w["WOAR"])

    return unless GOT_ID3V2
    system(%(id3v2 --WOAR "http://foo.bar" "#{TEMP_FILE}"))

    Mp3Info.open(TEMP_FILE) do |mp3|
      assert_equal "http://foo.bar", mp3.tag2["WOAR"]
    end
  end

  def test_reading2_2_tags
    load_fixture_to_temp_file("2_2_tagged")

    Mp3Info.open(TEMP_FILE) do |mp3|
      assert_equal "2.2.0", mp3.tag2.version
      expected_tag = { 
        "TCO" => "Hip Hop/Rap",
        "TP1" => "Grems Aka Supermicro",
        "TT2" => "Intro",
        "TAL" => "Air Max",
        "TEN" => "iTunes v7.0.2.16",
        "TYE" => "2006",
        "TRK" => "1/17",
        "TPA" => "1/1" }
      tag = mp3.tag2.dup
      assert_equal 4, tag["COM"].size
      tag.delete("COM")
      assert_equal expected_tag, tag

      expected_tag = { 
        "genre_s"       => "Hip Hop/Rap",
        "title"         => "Intro",
        #"comments"      => "\000engiTunPGAP\0000\000\000",
        "comments"      => "0",
        "year"          => 2006,
        "album"         => "Air Max",
        "artist"        => "Grems Aka Supermicro",
        "tracknum"      => 1 }
      # test universal tag
      assert_equal expected_tag, mp3.tag
    end
  end

  def test_writing_universal_tag_from_2_2_tags
    load_fixture_to_temp_file("2_2_tagged")

    Mp3Info.open(TEMP_FILE) do |mp3|
      mp3.tag.artist = "toto"
      mp3.tag.comments = "comments"
      mp3.flush
      expected_tag = { 
        "artist" => "toto",
        "genre_s" => "Hip Hop/Rap",
        "title" => "Intro",
        "comments" => "comments",
        "year" => 2006,
        "album" => "Air Max",
        "tracknum" => 1}

      assert_equal expected_tag, mp3.tag
    end
  end

  def test_remove_tag
    Mp3Info.open(TEMP_FILE) do |mp3|
      tag = mp3.tag
      tag.title = "title"
      tag.artist = "artist"
      mp3.close
      mp3.reload
      assert !mp3.tag1.empty?, "tag is empty"
      mp3.removetag1
      mp3.flush
      assert mp3.tag1.empty?, "tag is not empty"
    end
  end

  def test_good_parsing_of_a_pathname
    fn = "Freak On `(Stone´s Club Mix).mp3"
    FileUtils.cp(TEMP_FILE, fn)
    begin
      Mp3Info.open(fn) do |mp3|
        mp3.tag.title = fn
        mp3.flush
        if RUBY_VERSION[0..2] == "1.8"
          assert_equal fn, mp3.tag.title
        else
          assert_equal fn, mp3.tag.title.force_encoding("utf-8")
        end
      end
    ensure
      File.delete(fn)
    end
  end

  def test_audio_content
    require "digest/md5"

    expected_digest = nil
    Mp3Info.open(TEMP_FILE) do |mp3|
      mp3.tag1.update(DUMMY_TAG1)
      mp3.tag2.update(DUMMY_TAG2)
      mp3.flush
      assert mp3.hastag1?
      assert mp3.hastag2?
      assert mp3.tag2.io_position != 0
      expected_digest = compute_audio_content_mp3_digest(mp3)
    end

    Mp3Info.open(TEMP_FILE) do |mp3|
      mp3.removetag1
      mp3.removetag2
      mp3.flush
      assert !mp3.hastag1?
      assert !mp3.hastag2?
      got_digest = compute_audio_content_mp3_digest(mp3)
      assert_equal expected_digest, got_digest
    end
  end

  def test_audio_content_problematic
    load_fixture_to_temp_file("audio_content_fixture", false)
    Mp3Info.open(TEMP_FILE) do |mp3|
      expected_pos = 150
      audio_content_pos, audio_content_size = mp3.audio_content
      assert_equal expected_pos, audio_content_pos
      assert_equal File.size(TEMP_FILE) - expected_pos, audio_content_size
    end
  end

  def test_headerless_vbr_file
    mp3_length = 3
    load_fixture_to_temp_file("small_vbr_mp3")

    Mp3Info.open(TEMP_FILE) do |mp3|
      assert mp3.vbr
      assert_in_delta(mp3_length, mp3.length, 0.1)
      assert_in_delta(128, mp3.bitrate, 8)
    end
  end

  def test_parse_tags_disabled
    write_tag2_to_temp_file(DUMMY_TAG2)
    Mp3Info.open(TEMP_FILE, :parse_tags => false) do |mp3|
      assert mp3.tag.empty?
      assert mp3.tag1.empty?
      assert mp3.tag2.empty?
      mp3.tag["artist"] = "some dummy tag"
      mp3.tag2["TIT2"] = "title 2"
      mp3.flush
      # tag should not be written
      assert mp3.tag.empty?
      assert mp3.tag1.empty?
      assert mp3.tag2.empty?
    end
  end

  def test_string_io
    io = load_string_io
    Mp3Info.open(io) do |mp3|
      assert_mp3_info_are_ok(mp3)
    end
  end

  def test_trying_to_rename_a_stringio_should_raise_an_error
    io = load_string_io
    Mp3Info.open(io) do |mp3|
      assert_raises(Mp3InfoError) do
        mp3.rename("whatever_filename_is_error_should_be_raised.mp3")
      end
    end
  end

  def test_hastag_class_methods_with_a_stringio
    Mp3Info.open(TEMP_FILE) do |info| 
      info.tag1 = @tag
    end
    io = load_string_io
    assert(Mp3Info.hastag1?(io))

    written_tag = write_tag2_to_temp_file(DUMMY_TAG2)
    io = load_string_io
    assert(Mp3Info.hastag2?(io))
  end

  def test_convert_to_utf16_little_endian
    s = Mp3Info::EncodingHelper.convert_to("track's title €éàïôù", "utf-8", "utf-16")
    expected = "ff fe 74 00 72 00 61 00 63 00 6b 00 27 00 73 00 20 00 74 00 69 00 74 00 6c 00 65 00 20 00 ac 20 e9 00 e0 00 ef 00 f4 00 f9 00"
    assert_equal(expected, spy_bytes(s))
  end

  def test_unsynced_frame
    unsynched = "\xFF\x00\xE0\xFF\x00\x13\xFF\x00\x14".force_encoding('binary')
    resynched = "\xFF\xE0\xFF\x13\xFF\x14".force_encoding('binary')
    tag = ID3v2.new
    mock_io(tag, unsynched)

    tag.send(:add_value_to_tag2, 'foo1', 0, false)
    assert_equal(unsynched, tag.foo1)
    tag.send(:add_value_to_tag2, 'foo2', 0, true)
    assert_equal(resynched, tag.foo2)
  end

  def test_frame_flags
    tag = ID3v2.new

    flags = tag.send(:frame_flags, "\x00\x02".force_encoding('binary'))
    assert(flags[:unsync]) # bit 15 is 1

    flags = tag.send(:frame_flags, "\x00\x00".force_encoding('binary'))
    refute(flags[:unsync]) # # bit 15 is 0
  end

  def test_resync
    tag = ID3v2.new
    s = "\xFF\x00\xE0\xFF\x00\x13\xFF\x00\x14".force_encoding('binary')
    expected = "\xFF\xE0\xFF\x13\xFF\x14".force_encoding('binary')
    assert_equal(expected, tag.send(:resync, s))
  end

  # #################
  # to_bin
  # #################

  def test_to_bin_mixed_utf8_binary
    id3 = ID3v2.new
    id3.TIT2 = "€€€"
    id3.WOAF = 'http://url.com¨'
    id3.RVAD = 'http://url.com¨'
    assert_match /.*TIT2.*WOAF.*RVAD.*/, id3.to_bin
  end

  # #################
  # encode_tag
  # #################

  # encode : T***
  def test_encode_tag
    id3 = ID3v2.new
    assert_equal("01 ff fe 61 00 72 00 74 00 69 00 73 00 74 00 27 00 73 00 20 00 61 00 6c 00 62 00 75 00 6d 00 ac 20", spy_bytes(id3.send(:encode_tag, 'TPE1', "artist's album€")), 'TPE1')
    assert_equal("01 ff fe 74 00 72 00 61 00 63 00 6b 00 27 00 73 00 20 00 74 00 69 00 74 00 6c 00 65 00 ac 20", spy_bytes(id3.send(:encode_tag, 'TIT2', "track's title€")), 'TIT2')
  end

  # encode : COMM/USLT
  def test_encode_tag_comm_uslt
    id3 = ID3v2.new
    expected = "01 45 4e 47 fe ff 00 00 ff fe 63 00 6f 00 6d 00 6d 00 65 00 6e 00 74 00 ac 20"
    assert_equal(expected, spy_bytes(id3.send(:encode_tag, 'COMM', "comment€")), 'COMM')
    assert_equal(expected, spy_bytes(id3.send(:encode_tag, 'USLT', "comment€")), 'USLT')
    assert_not_equal(expected, spy_bytes(id3.send(:encode_tag, 'TPE1', "comment€")), 'T* are NOT treated like COMM/USLT')
  end

  # encode : W*** (urls)
  def test_encode_tag_urls
    id3 = ID3v2.new
    assert_equal("68 74 74 70 3a 2f 2f 75 72 6c 2e 63 6f 6d", spy_bytes(id3.send(:encode_tag, 'WOAF', "http://url.com")), "urls are always in latin1")
    assert_equal("68 74 74 70 3a 2f 2f 75 72 6c 2e 63 6f 6d e2 82 ac", spy_bytes(id3.send(:encode_tag, 'WOAF', "http://url.com€")), 'unicode chars are not accepted in latin1, but should not crash')
  end

  # encode : WXXX (user url). WXXX is a special case of W***, mixing utf16 for description and latin1 for content
  def test_encode_tag_wxxx
    id3 = ID3v2.new
    assert_equal("01 fe ff 00 00 68 74 74 70 3a 2f 2f 75 72 6c 2e 63 6f 6d", spy_bytes(id3.send(:encode_tag, 'WXXX', "http://url.com")))
    assert_equal("01 fe ff 00 00 68 74 74 70 3a 2f 2f 75 72 6c 2e 63 6f 6d e2 82 ac", spy_bytes(id3.send(:encode_tag, 'WXXX', "http://url.com€")), 'unicode chars are not accepted in latin1, but should not raise an exception')
  end

  def test_encode_frames_families
    id3 = ID3v2.new
    s = "unicode € string"
    # family 1 (TIT2-like)
    tit2 = spy_bytes(id3.send(:encode_tag, 'TIT2', s))
    tpe1 = spy_bytes(id3.send(:encode_tag, 'TPE1', s))
    tpe2 = spy_bytes(id3.send(:encode_tag, 'TPE2', s))
    # family 2 (COMM-like)
    comm = spy_bytes(id3.send(:encode_tag, 'COMM', s))
    uslt = spy_bytes(id3.send(:encode_tag, 'USLT', s))
    # family 3 (W***-like)
    woaf = spy_bytes(id3.send(:encode_tag, 'WOAF', s))
    woar = spy_bytes(id3.send(:encode_tag, 'WOAR', s))
    woas = spy_bytes(id3.send(:encode_tag, 'WOAS', s))
    # family 4 (WXXX-like)
    wxxx = spy_bytes(id3.send(:encode_tag, 'WXXX', s))

    assert(tit2 == tpe1 && tpe1 == tpe2, 'family 1')
    assert(comm == uslt, 'family 2')
    assert(woaf == woar && woar == woas, 'family 3')
    assert(tit2 != comm, 'family 1<>2')
    assert(tit2 != woar, 'family 1<>3')
    assert(wxxx != tit2, 'family 1<>4')
    assert(comm != woar, 'family 2<>3')
    assert(comm != wxxx, 'family 2<>4')
    assert(woar != wxxx, 'family 3<>4')
  end

  # #################
  # decode_tag
  # #################

  # decode : safe encoding when invalid byte sequence is found
  def test_decode_tag_safe_encoding
    id3 = ID3v2.new
    raw = "\x03\x61\xD2\x62"
    decoded = id3.send(:decode_tag, 'TIT2', raw)
    assert_equal("UTF-8", decoded.encoding.to_s)
    assert_equal("ab", decoded)
  end

  # decode : COMM/USLT
  def test_decode_tag_comm_uslt
    id3 = ID3v2.new
    raw = "\x01\x45\x4e\x47\xfe\xff\x00\x00\xff\xfe\x63\x00\x6f\x00\x6d\x00\x6d\x00\x65\x00\x6e\x00\x74\x00\xac\x20"
    assert_equal("comment€", id3.send(:decode_tag, 'COMM', raw), 'COMM')
    assert_equal("comment€", id3.send(:decode_tag, 'USLT', raw), 'USLT')
    assert_not_equal("comment€", id3.send(:decode_tag, 'TIT2', raw), 'T* are NOT treated like COMM/USLT')
  end
  
  # decode : W*** (urls)
  def test_decode_tag_urls
    id3 = ID3v2.new
    raw = "\x68\x74\x74\x70\x3a\x2f\x2f\x75\x72\x6c\x2e\x63\x6f\x6d"
    assert_equal("http://url.com", id3.send(:decode_tag, 'WOAF', raw), 'WOAF')
    assert_nil(id3.send(:decode_tag, 'WXXX', raw), 'WXXX')
  end

  # decode : WXXX (user url). WXXX is a special case of W***, mixing utf16 for description and latin1 for content
  def test_decode_tag_wxxx
    id3 = ID3v2.new
    raw = "\x01\xfe\xff\x00\x00\x68\x74\x74\x70\x3a\x2f\x2f\x75\x72\x6c\x2e\x63\x6f\x6d"
    assert_equal("http://url.com", id3.send(:decode_tag, 'WXXX', raw), 'WXXX')
  end

  def test_decode_frames_families
    id3 = ID3v2.new
    raw = "\x01\x45\x4e\x47\xfe\xff\x00\x00\xff\xfe\x63\x00\x6f\x00\x6d\x00\x6d\x00\x65\x00\x6e\x00\x74\x00\xac\x20"
    # family 1 (TIT2-like)
    tit2 = id3.send(:decode_tag, 'TIT2', raw)
    tpe1 = id3.send(:decode_tag, 'TPE1', raw)
    tpe2 = id3.send(:decode_tag, 'TPE2', raw)
    # family 2 (COMM-like
    comm = id3.send(:decode_tag, 'COMM', raw)
    uslt = id3.send(:decode_tag, 'USLT', raw)
    # family 3 (W***-like
    woaf = id3.send(:decode_tag, 'WOAF', raw)
    woar = id3.send(:decode_tag, 'WOAR', raw)
    woas = id3.send(:decode_tag, 'WOAS', raw)
    # family 4 (WXXX-like
    wxxx = id3.send(:decode_tag, 'WXXX', raw)

    assert(tit2 == tpe1 && tpe1 == tpe2, 'family 1')
    assert(comm == uslt, 'family 2')
    assert(woaf == woar && woar == woas, 'family 3')
    assert(tit2 != comm, 'family 1<>2')
    assert(tit2 != woar, 'family 1<>3')
    assert(wxxx != tit2, 'family 1<>4')
    assert(comm != woar, 'family 2<>3')
    assert(comm != wxxx, 'family 2<>4')
    assert(woar != wxxx, 'family 3<>4')
  end

  # #################
  # padding
  # #################

  #
  #
  #
  def test_padding
    # confirm we dont have any tag
    Mp3Info.open(TEMP_FILE) {|mp3| assert(mp3.tag2.empty?)}

    # let's write a title
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.TIT2 = "hello"}

    # check we've inserted padding
    tag_size = 0
    Mp3Info.open(TEMP_FILE) {|mp3|  tag_size = mp3.tag2.tag_length}
    assert(tag_size >= ID3v2::DEFAULT_PADDING)

    # let's write a longer title
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.TIT2 = "hello12345678901234567890234567890123456789012345678902345678901234567890"}

    # check tag size has not changed
    Mp3Info.open(TEMP_FILE) {|mp3|  assert(tag_size == mp3.tag2.tag_length)}

    # let's write a title longer than padding
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.TIT2 = "x" * ID3v2::DEFAULT_PADDING}

    # check tag size has now changed - allocating a second padding block (progressive padding)
    Mp3Info.open(TEMP_FILE) {|mp3|
      assert(mp3.tag2.tag_length > tag_size);
      assert(mp3.tag2.tag_length > 2 * ID3v2::DEFAULT_PADDING);
      tag_size = mp3.tag2.tag_length
    }

    # let's write again a shorter title
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.TIT2 = "hello world"}

    # check tag size has not changed (still 2 padding block, that we're not shrinking)
    Mp3Info.open(TEMP_FILE) {|mp3|  assert(tag_size == mp3.tag2.tag_length)}
  end

  #
  #
  #
  def test_padding_without_padding
    # confirm we dont have any tag
    Mp3Info.open(TEMP_FILE) {|mp3| assert(mp3.tag2.empty?)}

    # let's write a title, without padding
    Mp3Info.open(TEMP_FILE, {:padding => false}) {|mp3| mp3.tag2.TIT2 = "hello"}

    # check tag size is not including padding
    Mp3Info.open(TEMP_FILE) {|mp3|  assert(mp3.tag2.tag_length < ID3v2::DEFAULT_PADDING)}
  end

  #
  #
  #
  def test_padding_not_rewriting_file
    last_inode = File.stat(TEMP_FILE).ino

    # let's write a title
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.TIT2 = "hello"}
    new_inode = File.stat(TEMP_FILE).ino
    assert(last_inode != new_inode, "there was no tag => we had to write a new file")
    last_inode = new_inode

    # let's write a longer title
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.TIT2 = "hello12345678901234567890234567890123456789012345678902345678901234567890"}
    new_inode = File.stat(TEMP_FILE).ino
    assert(last_inode == new_inode, "we've used the padding => write in the original")
    last_inode = new_inode

    # let's write a title longer than padding
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.TIT2 = "x" * ID3v2::DEFAULT_PADDING}
    new_inode = File.stat(TEMP_FILE).ino
    assert(last_inode != new_inode, "padding wasnt enough, we had to write a new file")
    last_inode = new_inode

    # let's write again a shorter title
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.TIT2 = "hello world"}
    new_inode = File.stat(TEMP_FILE).ino
    assert(last_inode == new_inode, "padding is large enough, write in the original")
    last_inode = new_inode
  end

  #
  #
  #
  def test_padding_size_is_configurable
    custom_padding = 2 * ID3v2::DEFAULT_PADDING
    
    # let's write a title
    Mp3Info.open(TEMP_FILE, {:padding_size => custom_padding}) {|mp3| mp3.tag2.TIT2 = "hello"}

    # check we've inserted the custom padding size, not the default
    tag_size = 0
    Mp3Info.open(TEMP_FILE) {|mp3|  tag_size = mp3.tag2.tag_length}
    assert(tag_size >= custom_padding)
  end

  #
  #
  #
  def test_padding_size_0_is_equivalent_to_no_padding
    tag_size = 0

    # let's write a title with padding disabled and get resulting tag size
    Mp3Info.open(TEMP_FILE, {:padding => false}) {|mp3| mp3.tag2.TIT2 = "hello"}
    Mp3Info.open(TEMP_FILE) {|mp3|  tag_size = mp3.tag2.tag_length}

    # let's write a title with padding size 0
    Mp3Info.open(TEMP_FILE, {:padding_size => 0}) {|mp3| mp3.tag2.TIT2 = "hello"}

    # check the size
    Mp3Info.open(TEMP_FILE) {|mp3|  assert(mp3.tag2.tag_length == tag_size)}
  end
  
  #
  #
  #
  def test_padding_on_remove_tag
    original_filesize = File.size(TEMP_FILE)

    # write tag with smart_padding
    Mp3Info.open(TEMP_FILE, {:smart_padding => false}) {|mp3| mp3.tag2.TIT2 = "hello"}
    filesize = File.size(TEMP_FILE)
    assert (filesize > original_filesize)

    Mp3Info.removetag2(TEMP_FILE)
    filesize = File.size(TEMP_FILE)
    assert (filesize == original_filesize)
  end
  
  
  # #########################
  # smart_padding
  # #########################
  
  #
  #
  #
  def test_smart_padding
    min_tag_size = 200.kilobytes

    # advanced padding disabled
    Mp3Info.open(TEMP_FILE, {:smart_padding => false}) {|mp3| mp3.tag2.TIT2 = "hello"}
    Mp3Info.open(TEMP_FILE) {|mp3|  assert(mp3.tag2.tag_length < min_tag_size, 'smart_padding disabled')}

    # let's write a title with smart_padding (activated by default) to fill min_tag_size
    Mp3Info.open(TEMP_FILE, {:minimum_tag_size => min_tag_size}) {|mp3| mp3.tag2.TIT2 = "new title"}
    Mp3Info.open(TEMP_FILE) {|mp3|assert(mp3.tag2.tag_length >= min_tag_size, 'smart_padding enabled')}

    # let's confirm now that we can write large frame without rewriting the file
    inode = File.stat(TEMP_FILE).ino
    Mp3Info.open(TEMP_FILE) {|mp3| mp3.tag2.APIC = "x" * (min_tag_size - 50) } # -50 to allow the rest of infos written above
    Mp3Info.open(TEMP_FILE) {|mp3|  assert(mp3.tag2.tag_length >= min_tag_size, 'smart_padding in use')}
    assert(inode == File.stat(TEMP_FILE).ino, 'enough padding to write in the original') # still the same file
  end

  #
  #
  #
  def test_smart_padding_on_remove_tag
    min_tag_size = 200.kilobytes
    original_filesize = File.size(TEMP_FILE)

    # write tag with smart_padding
    Mp3Info.open(TEMP_FILE, {:minimum_tag_size => min_tag_size}) {|mp3| mp3.tag2.TIT2 = "hello"}
    filesize = File.size(TEMP_FILE)
    assert (filesize > original_filesize && filesize > min_tag_size)

    # remove the tag and assert padding has been removed too
    Mp3Info.removetag2(TEMP_FILE)
    filesize = File.size(TEMP_FILE)
    assert (filesize == original_filesize)
  end

  #
  #
  #
  def test_smart_padding_custom_callback
    # default behaviour exists
    Mp3Info.open(TEMP_FILE) {|mp3| assert(mp3.tag2.send(:minimum_tag_size, 50.megabytes) > 0)}

    # custom callback
    custom_minimum_tag_size = lambda { |filesize|
      return filesize == 123 ? 456 : 789
    }

    # custom callback is used rather than default
    Mp3Info.open(TEMP_FILE, {:minimum_tag_size_callback => custom_minimum_tag_size}) {|mp3|
      assert_equal(456, mp3.tag2.send(:minimum_tag_size, 123))
      assert_equal(789, mp3.tag2.send(:minimum_tag_size, 0))
    }
  end

  # #########################
  # helpers
  # #########################

  def compute_audio_content_mp3_digest(mp3)
    pos, size = mp3.audio_content
    data = File.open(mp3.filename) do |f|
      f.seek(pos, IO::SEEK_SET)
      f.read(size)
    end
    Digest::MD5.new.update(data).hexdigest
  end

  def write_tag2_to_temp_file(tag)
    Mp3Info.open(TEMP_FILE) do |mp3|
      mp3.tag2.update(tag)
    end
    return Mp3Info.open(TEMP_FILE) { |m| m.tag2 }
    #system("cp -v #{TEMP_FILE} #{TEMP_FILE}.test")
  end

  def random_string(size)
    out = ""
    size.times { out << rand(256).chr }
    out
  end

  def assert_mp3_info_are_ok(mp3)
    assert_equal(1, mp3.mpeg_version)
    assert_equal(3, mp3.layer)
    assert_equal(false, mp3.vbr)
    assert_equal(128, mp3.bitrate)
    assert_equal("JStereo", mp3.channel_mode)
    assert_equal(44100, mp3.samplerate)
    assert_equal(0.1305625, mp3.length)
    assert_equal({:original => true, 
                  :error_protection => false, 
                  :padding => false, 
                  :emphasis => 0, 
                  :private => true, 
                  :mode_extension => 2, 
                  :copyright => false}, mp3.header)
  end

  def load_string_io(filename = TEMP_FILE)
    io = StringIO.new
    data = File.read(filename)
    io.write(data)
    io.rewind
    io
  end

  FIXTURES = YAML::load_file( File.join(File.dirname(__FILE__), "fixtures.yml") )

  def load_fixture_to_temp_file(fixture_key, zlibed = true)
    # Command to create a gzip'ed dummy MP3
    # $ dd if=/dev/zero bs=1024 count=15 | \
    #   lame --quiet --preset cbr 128 -r -s 44.1 --bitwidth 16 - - | \
    #   ruby -rbase64 -rzlib -ryaml -e 'print(Zlib::Deflate.deflate($stdin.read)'
    # vbr:
    # $ dd if=/dev/zero of=#{tempfile.path} bs=1024 count=30000 |
    #     system("lame -h -v -b 112 -r -s 44.1 --bitwidth 16 - /tmp/vbr.mp3
    #
    # this will generate a #{mp3_length} sec mp3 file (44100hz*16bit*2channels) = 60/4 = 15
    # system("dd if=/dev/urandom bs=44100 count=#{mp3_length*4}  2>/dev/null | \
    #        lame -v -m s --vbr-new --preset 128 -r -s 44.1 --bitwidth 16 - -  > #{TEMP_FILE} 2>/dev/null")
    content = FIXTURES[fixture_key]
    if zlibed
      content = Zlib::Inflate.inflate(content)
    end

    File.open(TEMP_FILE, "w") do |f| 
      f.write(content)
    end
  end
  
  def spy_bytes(s)
    s.bytes.map{|b| b.to_s(16).rjust(2, '0')}.join(" ")
  end

  def mock_io(tag, s)
    mock = {}
    eval <<-EOF
      def mock.read(*args)
        "#{s}".force_encoding('binary')
      end
    EOF
    tag.instance_variable_set("@io", mock)
  end
  
=begin

  def test_encoder
    write_to_temp
    info = Mp3Info.new(TEMP_FILE)
    assert(info.encoder == "Lame 3.93")
  end

  def test_vbr
    mp3_vbr = Base64.decode64 <<EOF

EOF
    File.open(TEMP_FILE, "w") { |f| f.write(mp3_vbr) }
    info = Mp3Info.new(TEMP_FILE)
    assert_equal(info.vbr, true)
    assert_equal(info.bitrate, 128)
  end
=end
end
