# coding:utf-8
# License:: Ruby
# Author:: Guillaume Pierronnet (mailto:guillaume.pierronnet@gmail.com)
# Website:: http://ruby-mp3info.rubyforge.org/

class Mp3Info 
  module HashKeys #:nodoc:
    ### lets you specify hash["key"] as hash.key
    ### this came from CodingInRuby on RubyGarden
    ### http://www.rubygarden.org/ruby?CodingInRuby
    def method_missing(meth,*args)
      m = meth.id2name
      if /=$/ =~ m
	self[m.chop] = (args.length<2 ? args[0] : args)
      else
	self[m]
      end
    end
  end  
  
  class ::String
    if RUBY_VERSION < "1.9.0"
      alias getbyte []
    end

    #
    #  "1\xD23".encode!("UTF-8").valid_encoding? => false # wtf!!
    #  "1\xD23".encode!("UTF-8", invalid: :replace, undef: :replace, replace: '').valid_encoding? => false # wtf!!
    #  "1\xD23".force_encoding("BINARY").encode!("UTF-8", invalid: :replace, undef: :replace, replace: '').valid_encoding? => true # duh!
    #  "1\xD23".safe_encode! => "13" # aaaah
    #
    #  http://blog.tddium.com/2012/04/03/down-the-rabbit-hole-with-utf-8-yaml-and-rspec/
    #
    def safe_encode!(encoding = 'UTF-8')
      self.encode!(encoding) rescue nil
      self.force_encoding("BINARY").encode!(encoding, invalid: :replace, undef: :replace, replace: '') unless self.valid_encoding?
      self
    end

  end

  module Mp3FileMethods #:nodoc: 
    if RUBY_VERSION < "1.9.0"
      def getbyte
        getc
      end
    end
                        
    def get32bits
      (getbyte << 24) + (getbyte << 16) + (getbyte << 8) + getbyte
    end

    def get_syncsafe
      (getbyte << 21) + (getbyte << 14) + (getbyte << 7) + getbyte
    end                 
  end

  class EncodingHelper #:nodoc:
    def self.convert_to(value, from, to)
      if RUBY_1_8
        if to == "iso-8859-1"
          to = to + "//TRANSLIT"
        end
        ruby_18_encode(from, to, value)
      else
        if to == "utf-16"
          ("\uFEFF" +  value).encode("UTF-16LE")
        else
          value.encode(to) rescue value.force_encoding('iso-8859-1').encode(to)
        end
      end
    end

    def self.convert_from_iso_8859_1(value)
      if RUBY_1_8
        ruby_18_encode("utf-8", "iso-8859-1", value)
      else
        value.force_encoding("iso-8859-1").encode("utf-8")
      end
    end

    def self.ruby_18_encode(from, to, value)
      Iconv.iconv(to, from, value).first
    end

    def self.decode_utf16(out)
      if RUBY_1_8
        convert_to(out, "UTF-8", "UTF-16")
      else
        if out.bytes.first == 0xff
          tag_encoding = "UTF-16LE"
        else
          tag_encoding = "UTF-16BE"
        end
        out = out.dup.force_encoding(tag_encoding)[1..-1]
      end
    end
  end
end
