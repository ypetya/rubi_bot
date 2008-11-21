# INSTALL:
#
# Dependencies
#
# native install from source: libmemcached
# gem: memcached check COMPATIBILITY for libmemcached
# gem: echoe for memcached gem
# Create a symlink ln -s /usr/local/lib/libmemcached.so.2 /usr/lib/.
#  ldconfig /var/lib/gems/1.8/gems/memcached-0.11/lib/rlibmemcached.so
#  ldd /var/lib/gems/1.8/gems/memcached-0.11/lib/rlibmemcached.so => should be alright
#
require 'memcached'

MEMCACHED_CONFIG = 'localhost:11211'
MEMCACHED_ENABLED = true

# TIMEOUT in seconds (nil => no timeout specified)
#
MEMCACHED_TIMEOUT = nil

#

class ChatMessage
  attr_accessor :status,:body,:id,:chatname,:fromhandle,:type
  def initialize id = nil
    @id = id
  end
end

class User
  attr_accessor :id,:fullname,:sex,:birthday,:city
  def initialize id = nil
    @id = id
  end
end

class Chat
  attr_accessor :members,:friendlyname,:topic,:id,:chats
  # asynchron prop not supported by SkypeR :(
  attr_accessor :chatmessages
  def initialize id = nil
    @id = id
  end
end

#general cache to store specifient type of objcets. with safe get and save.
class Cache
  attr_accessor :chats,:chatmessages,:users

  alias try instance_eval


  # to find classnames, at create
  CLASSHELPER = {:chatmessage => 'ChatMessage', :user => 'User', :chat => 'Chat'}

  def initialize
    @debug = DEBUG
    @cache = Memcached.new(MEMCACHED_CONFIG) if MEMCACHED_ENABLED == true
  end

  def method_missing(m,*args, &block)
    comm = m.to_s
    case
    when comm =~ /^get_([^_]*)_([^_]*)/
      comm.gsub(/^get_([^_]*)_([^_]*)/) { return get_safe( $1, $2, *args)}
    when comm =~ /^set_([^_]*)_([^_]*)/
      comm.gsub(/^set_([^_]*)_([^_]*)/) { return set_safe( $1, $2, *args)}
    when comm =~ /^get_([a-z]*)/
      comm.gsub(/^get_([a-z]*)/){ return get_obj( $1,*args) }
    when comm =~ /^set_([a-z]*)/
      comm.gsub(/^set_([a-z]*)/){ return set_obj( $1,*args) }
    else
      super.send m,*args, &block
    end
  end

  #saves object cache to dir/<object>s.yml
  def store_to_dir dir
    begin
      
      Dir.mkdir(dir) unless File.exists?(dir)
      instance_variables.each{|var|
        #a chatinfokat nem tároljuk le, mert jó ha lekérdezi új üzenetkor

        next unless var =~ /_ids/

        i = 0
        str = <<-EOT
          File.open(File.join(dir,\"#{var.gsub('@','').gsub('_id','')}.yml\"),'w'){|f| 
            #{var}.each{|id| 
              f.write(Hash[id.to_s.to_sym,get_obj('#{var.gsub('@','').gsub('_ids','')}',id.to_s)].to_yaml)}}
EOT
        try( str )
        try("puts \"Cache stored #{var.gsub('_id','')}: \#{#{var}.length} instances to disk.\"")}
    
    rescue Exception => e
      puts e.message
      puts "Backtrace:"
      e.backtrace.each {|line| puts line }
    end
  end

  #load instance variables from file system.. :)
  def load_from_dir dir
    Dir[File.join(dir,"*.yml")].each do |file|
      begin
        var_name = File.basename(file).gsub(/s\.yml/,'')
        my_count = 0
        File.open(file) do |my_file|
          last_obj = nil
          while line = my_file.gets do
            if line == "--- \n" #uj yaml objekt :)
              if last_obj
                o = YAML.load(last_obj) 
                set_obj_val var_name,o.keys[0],o.values[0]
                my_count = my_count + 1
              end
              last_obj = ''
            end
            last_obj = last_obj + line
          end
          o = YAML.load(last_obj)
          set_obj_val var_name,o.keys[0],o.values[0]
          my_count = my_count + 1
        end

        try("puts \"Cache loaded @#{var_name}: #{my_count} instances from disk.\"")
      rescue Exception => e
        puts "Can not load #{file}."
        puts e.message
      end
    end
  end

  #saves object cache to dir/<object>s.yml
  def store_to_dir dir
    begin
      Thread.exclusive(){  
        Dir.mkdir(dir) unless File.exists?(dir)
        instance_variables.each{|var|
          #a chatinfokat nem tároljuk le, mert jó ha lekérdezi új üzenetkor

          next unless var =~ /_ids/

          i = 0
          str = <<-EOT
            File.open(File.join(dir,\"#{var.gsub('@','').gsub('_id','')}.yml\"),'w'){|f| 
              #{var}.each{|id| 
                f.write(Hash[id.to_s.to_sym,get_obj('#{var.gsub('@','').gsub('_ids','')}',id.to_s)].to_yaml)}}
  EOT
          try( str )
          try("puts \"Cache stored #{var.gsub('_id','')}: \#{#{var}.length} instances to disk.\"")}
      }
    rescue Exception => e
      puts e.message
      puts "Backtrace:"
      e.backtrace.each {|line| puts line }
    end
  end

  #load instance variables from file system.. :)
  def load_from_dir dir
    Dir[File.join(dir,"*.yml")].each do |file|
      begin
        var_name = File.basename(file).gsub(/s\.yml/,'')
        my_count = 0
        File.open(file) do |my_file|
          last_obj = nil
          while line = my_file.gets do
            if line == "--- \n" #uj yaml objekt :)
              if last_obj
                o = YAML.load(last_obj) 
                set_obj_val var_name,o.keys[0],o.values[0]
                my_count = my_count + 1
              end
              last_obj = ''
            end
            last_obj = last_obj + line
          end
          o = YAML.load(last_obj)
          set_obj_val var_name,o.keys[0],o.values[0]
          my_count = my_count + 1
        end

        try("puts \"Cache loaded @#{var_name}: #{my_count} instances from disk.\"")
      rescue Exception => e
        puts "Can not load #{file}."
        puts e.message
      end
    end
  end 
  
  unless MEMCACHED_ENABLED == true

    #returns with message attribute if it exists else nil
    def get_safe(obj,attr,id)
      a = try("@#{obj}s['#{id}'.to_sym].#{attr} if defined?(@#{obj}s['#{id}'.to_sym].#{attr})")
      if a
        print "+" if @debug == true
        return a
      else
        print "-"
        return nil
      end
    end

    #return object from cache, if it exists else nil
    def get_obj(obj,id)
      a = try("@#{obj}s['#{id}'.to_sym] if defined?(@#{obj}s['#{id}'.to_sym])")
      if a
        print "+" if @debug == true
        return a
      else
        print "-"
        return nil
      end
    end

  protected
   #creates new object if it doesnot exists in sepecified list :)
    def set_safe(obj,attr,id,value)
      create_new_object_cache obj
      try("@#{obj}s['#{id}'.to_sym]= #{CLASSHELPER[obj.to_sym]}.new('#{id}') unless @#{obj}s['#{id}'.to_sym]")
      if value.is_a?(Array)
        a = try("@#{obj}s['#{id}'.to_sym].#{attr}= #{value.inspect}")
      elsif value.is_a?(String)
        a = try("@#{obj}s['#{id}'.to_sym].#{attr}= '#{value}'")
      elsif value.is_a?(Fixnum)
        a = try("@#{obj}s['#{id}'.to_sym].#{attr}= '#{value}'")
      else
        puts "Unknown type to store to cache.(#{value.class})"
      end
      print "\#" if @debug == true if a
      return value
    end

    def create_new_object_cache obj
      try("@#{obj}s={} unless @#{obj}s")
    end

  else
  # MEMCACHED_ENABLED!

    #returns with message attribute if it exists else nil
    def get_safe(obj,attr,id)
      a = get_obj(obj,id)
      return try("a.#{attr}") if a and a.respond_to? attr
      #puts attr
    end

    #return object from cache, if it exists else nil
    def get_obj(obj,id)
      begin
        a = @cache.get "#{obj}_#{id}"
        print "+" if @debug == true
        return YAML.load(a)
      rescue
      end
      #puts id.inspect
      print "-"
    end

  protected

    def set_obj_val(obj_name,id,value)
      return unless value
      #puts id.inspect
      print "\#" if @debug == true
      if MEMCACHED_TIMEOUT
        @cache.set "#{obj_name}_#{id}",value.to_yaml,MEMCACHED_TIMEOUT
      else
        @cache.set "#{obj_name}_#{id}",value.to_yaml 
      end
      try "@#{obj_name}_ids=[] unless defined? @#{obj_name}_ids"
      try("@#{obj_name}_ids << id unless @#{obj_name}_ids.include? id")
    end

    #creates new object if it doesnot exists in sepecified list :)
    def set_safe(obj,attr,id,value)
      a = try("#{CLASSHELPER[obj.to_sym]}.new('#{id}')") unless a = get_obj(obj,id)
        
      unless [Array,String,Fixnum].select{|type| value.is_a?(type)}.empty?
        try("a.#{attr}=#{value.inspect}")
      else
        puts "Unknown type to store to cache.(#{value.class})"
      end
      set_obj_val obj,id,a
      return value
    end

  end

  #safe set sepcified objects attribute
  def set_obj(obj,id,attr,value)
    a = set_safe(obj,attr,id,value)
    return a if a
    nil
  end

end
