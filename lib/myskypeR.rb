require 'rubygems'
require 'readline'
require 'optparse'
require 'logger'
require 'skyper.rb'
require 'fileutils'
require 'dbus'

#{{Szinkron kommunikációnál ennyi sec-t várunk a DBUS-válaszra
TIMEOUT = 15
#}}


class Test < ::DBus::Object
  def initialize name
    super name
  end
  dbus_interface 'com.Skype.API.Client' do
    dbus_method :Notify,'in string:s' do |string|
      puts "retyvedek#{string}"
    end
  end
end
module SkypeR
  module Service
    class Application
      #async [] pufferek 
      attr_accessor :missed_chats,:missed_messages,:connstatus

      def initialize(name, protocol_num = 5)
       
        @missed_chats = []
        @missed_messages = []
        @missed_chats_puff = []
        @connstatus = []
        @global_res = []

        remote_bus = ::RBus.session_bus
       
        service_dbus = remote_bus.service('org.freedesktop.DBus')

        #és elkérjük a skype service-t
        skype_service_name = 'com.Skype.API'
        object_path = '/com/Skype'
        @api_object = remote_bus.get_object(skype_service_name, object_path)
        
        #Notify-k kezelése
        #
        # << ő ezen hív minket befelé
        @api_object.connect!(:Notify, :member => 'Notify', :type => 'method_call', :path => '/com/Skype/Client', :interface => 'com.Skype.API.Client') {|s|
            my_arr = s.split()
#            puts s
            if my_arr.size == 2 and not ((my_arr[0] =~ /#/) == 0)
              #Státusz üzenet. köszönjük
              var,value = my_arr
              #instance_eval("puts 'Status changed #{var}->#{value}' if defined?(@#{var.downcase}) and @#{var.downcase} != '#{value}'")
#              instance_eval("@#{var.downcase}='#{value}'")
              @connstatus_last = value
              Thread.exclusive(){ @connstatus << value if @connstatus_last != value} if var == 'CONNSTATUS'
              return ['']
            else
              #hogyha nekünk érkezett vmi id-vel válasz, akkor tároljuk csak le.
              if( (my_arr[0] =~ /#/) == 0)
                Thread.exclusive(){@global_res << s}
              else
                s.gsub(/CHAT\s([^\s]*)\sACTIVITY_TIMESTAMP\s([0-9]*)/){
                  chat_id,ts,ts = $1,$2,$3
                  Thread.exclusive(){ @missed_chats_puff << chat_id }
                  print 'iC'
                  return ['']
                }
                s.gsub(/CHATMESSAGE\s([0-9]+)\sSTATUS\sRECEIVED/){
                  msg_id = $1
                  Thread.exclusive(){
                    @missed_chats << @missed_chats_puff.delete_at(0)
                    @missed_messages << msg_id
                  }
                  print 'im'
                  return ['']
                }

                #ezek a kliensen történő egyéb események hatására érkező infók, amit nem kezelünk (még)
                puts s
                #return ['']
              end
            end
          return ['']
        }
        # >>  mi ezen kommunikálunk kifelé
        @api_object.interface!(skype_service_name)
        @application_name = name
        # @invoked_commands = Hash.new
      end
      # ez itt egy dbus-os service publikálás és hívás.
      # mivel sikerült működésre bírni az RBus-szal ezért erre nincs szükség.
      def init_callback
        STDOUT.sync = true
        remote_bus_dbus = ::DBus.session_bus
        my_service = remote_bus_dbus.request_service("com.Skype.API.Client")
        exported_obj = Test.new('/com/Skype/Client')
        my_service.export(exported_obj)
        Thread.new do 
          begin
            main = DBus::Main.new
            main << remote_bus_dbus
            main.run
          rescue Exception => e
            puts e.message
            puts "Backtrace:"
            e.backtrace.each {|line| puts line }
          end
         end
         ms = remote_bus_dbus.service('com.Skype.API.Client')
         o = ms.object('/com/Skype/Client')
         o.introspect
         o.default_iface = 'com.Skype.API.Client'
         o.Notify 'szevasz'
      end

      # segéd fv. biztonságosan ránéz az aktuális üzenetre és true,ha nekünk jött
      def not_for_us_thread_safe_sync command_id
        Thread.exclusive(){ 
          @res == nil or (@res.split[0] != "##{command_id}") 
        }
      end

      # segéd fv. biztonságosan ránéz az aktuális üzenetre és true,ha nekünk jött
      def not_for_us_thread_safe_async command_id
        Thread.exclusive(){ 
          @global_res.empty? or !@global_res.select{|s| s.split[0] == "##{command_id}"} 
        }
      end

      #asynchron message handleing to avoid skype for hang
      def invoke(command, timeout = TIMEOUT)
        @global_res = []
        begin
          ::Timeout.timeout(timeout) {
            
            authenticate

            command_string = "##{command.command_id} #{command.statement}"
            #puts command_string
            @api_object.Invoke(command_string){|async_result|
              @res = nil
              
              while @res == nil do
                Thread.pass
                @res = async_result.dup
              end
            }
            # megvárjuk, amíg jön valami értelmes.
            # az "" is értelmes, lásd lentebb
            while not_for_us_thread_safe_sync(command.command_id) do
              break if @res == ""
              Thread.pass
            end
            return @res if @res != ""
          }
          # "" -> ide akkor jutunk, ha asszinkron 
          # visszahívásra várunk ezért most várjuk, hogy
          # megérkezzék az adat.
          while not_for_us_thread_safe_async(command.command_id) do
            #had játszadozzon üzenetküldéssel a skype, ha akar, mégiscsak ez egy asszinkron üzenet..
            sleep(1)

            Thread.pass
          end
          Thread.exclusive(){
            @res = @global_res.select{|s| s.split[0] == "##{command.command_id}"}.shift.dup
          }
          return @res
        rescue ::Timeout::Error
           print 't' if DEBUG == true
        end
      end

      def authenticate(protocol_num = 5)
        result = nil
        name_command = SkypeR::Service::CommandMessage.new("NAME #{@application_name}")
        result = @api_object.Invoke(name_command.statement)
        puts result unless result =~ /PROTOCOL|OK/
        protocol_command = SkypeR::Service::CommandMessage.new("PROTOCOL #{protocol_num}")
        result = @api_object.Invoke(protocol_command.statement)
        puts result unless result =~ /PROTOCOL|OK/
      end
    end # of Application
  end
end

module SkypeR
  LOGGER = nil
  class Arguments < Hash
    def initialize(args)
      super()
      # default values
      opts = ::OptionParser.new do |opts|
        opts.banner = "Usage: #$0 [options]"
        opts.on('-n', '--name [STRING]', 'application name to access Skype') do |string|
          self[:name] = string || '$'
        end

        opts.on('-l', '--log [STRING]', 'log file path') do |string|
          self[:log] = string || '$'
        end

        opts.on_tail('-h', '--help', 'display this help') do
          puts opts
          exit
        end
      end
      opts.parse(args)
    end
  end

  SKYPE = Service::Application.new('test')

  class REPL

    application = nil

    def initialize(name, log = nil, parse = false)
      @debug = false
      @application = SKYPE
      @parse = false
      @headers = []

      FileUtils::mkdir(File.dirname(log)) unless File.exists?(log)

      @logger = Logger.new(log ? log : $stderr)
    end


    def skype_command(command_statement)
      command_message = Service::CommandMessage.new(command_statement)
    end

    def skype_response(response_statement, response_instance)
      response = Service::ResponseMessage.new(response_statement, response_instance)
      result = @application.parse(response)
    end

    def skype_exit
      raise
    end

    def input_loop
      loop do
        line = Readline.readline('SkypeAPI> ')
        break unless line
        line.chomp!
        if line.empty?
 	  sleep(1)
	  puts '.'
          next
        else
          @logger.debug("INPUT> #{line}")
          case line
          when /^exit$/
            puts "See you again."
            @logger.debug("OUTPUT> See you again.")
            return
          else
            response_statement = nil
            command_message = SkypeR::Service::CommandMessage.new(line)
            response_statement = @application.invoke(command_message, 30)
            
            unless response_statement.empty?
              puts response_statement
              response_id, response_statement = split_response(response_statement)
              puts "=> #{response_statement}"
              @logger.debug("OUTPUT> #{response_statement}")
            end
          end
        end
        Readline::HISTORY.push(line)
      end
      @interpreter.close

    end # of input_loop method

    private
    def split_response(response_statement)
      if match = Regexp.new(/(#[0-9]+) (.*)$/).match(response_statement.to_s)
        [match[1], match[2]]
      else
        p "#{response_statement}"
        raise
      end
    end
  end # of Service
end # of SkypeR
