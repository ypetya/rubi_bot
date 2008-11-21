require 'lib/myskypeR.rb'
require 'lib/message_system.rb'
require 'lib/rubi_logic.rb'

DEBUG = true
RUBI_BOT_VERSION = '0.85'
MODES = [:Standalone,:WithSkyepAPIConsole]
MODE = :Standalone #:WithSkypeAPIConsole #:Standalone

class MyStore
  APP_NAME = 'test'
  SKYPEAPI_CONSOLE_LOG_FILE = 'log/iskype.log'
  DATA_DIRECTORY = 'data'
  Rubi = MessageSystem.new
  Logic = RubiLogic.new
end

def receive_sync
  #missed chats
  MyStore::Rubi.retreive_missed_chats.each { |chat| MyStore::Logic.enter_chat(chat) }
  MyStore::Rubi.missed_chatmessages.each{ |msg| MyStore::Logic.new_message(msg)# if msg.fromhandle != CONST[:test_acc]
  }
end

#ez itt az asynkron válaszüzenetek feldolgozása :), amit a skype küldött
def receive_async
  new_mess = nil
  MyStore::Rubi.get_async_chats{|chat| MyStore::Logic.enter_chat(chat) }
  new_mess ||= MyStore::Rubi.get_async_messages{|msg| MyStore::Logic.new_message(msg) if msg.fromhandle != CONST[:test_acc]}

  receive_sync if new_mess
end

def logic_reload
  puts 'Logic: Reload..'
  instance_eval( File.read('lib/rubi_logic.rb') )
end

def save_cache
  puts 'Cache: Auto Storing data to disk...'
  MyStore::Rubi.save_cache_to_filesystem MyStore::DATA_DIRECTORY
end

def user_auth_sync
  MyStore::Rubi.receive_userswaitingmyauthorization.each{ |user| MyStore::Logic.new_userauthorizationrequest user }
end

def status_changed
  MyStore::Rubi.status_changed do |status| 
    if status == CONST[:online] 
      send_test_message
      receive_sync
    end
  end
end

def send_test_message
  MyStore::Rubi.send_chatmessage CONST[:test_acc],'test'
end

CONST= {
  :test_acc => 'echo123',
  :online => 'ONLINE',
  :offline => 'OFFLINE',
  :timer => {
    :tick => 0.1,
    :tick_by_console => 100,

    :reset_at => 20000,     #-
    :auth => 18000,         #sync
    :save_cache => 18100,   #-
    :logic_reload => 3000,  #-
    :get_sync => 20001,   #sync
    :conn_status => 300,    #async
    :process => 1          #async
  }
}

begin
  threads = []
  
  puts "Rubi_bot(v#{RUBI_BOT_VERSION} loading... (exit with Ctrl+C)"
  begin
    MyStore::SkypeR_Console = SkypeR::REPL.new(MyStore::APP_NAME, MyStore::SKYPEAPI_CONSOLE_LOG_FILE, false)
  rescue Exception => e
    puts e.message
    puts "Backtrace:"
    e.backtrace.each {|line| puts line }
  end

  current_status = 'ONLINE'
  counter = 0
  #answerer thread
  threads << Thread.new do
    begin
      sleep 1 until defined?(MyStore::SkypeR_Console)
      MyStore::Logic.start
      puts 'GetMessage Thread running...'
      while true
        begin
          sleep(MODE == :Standalone ? CONST[:timer][:tick] : CONST[:timer][:tick_by_console])
          counter += 1
          #Authorizer: szinkron időközönként bekérdezünk és mindenkit elfogadunk
          user_auth_sync if(counter % CONST[:timer][:auth] == 1)
          #Autosaver: időközönként elmentjük a memóriánkat
          save_cache if(counter % CONST[:timer][:save_cache] == 0)
          #AutoLogic loader: időközönként betöltjük a logikánkat, hátha kaptunk új agyat.
          logic_reload if (counter % CONST[:timer][:logic_reload] == 0)
          #szinkron üzenetek check
          receive_sync if(counter % CONST[:timer][:get_sync] == 1)
          #feldolgozzuk a már hozzánk beérkezett üzeneteket
          receive_async if(counter % CONST[:timer][:process] == 0)
          #Connectionstatus változás 
          status_changed if(counter % CONST[:timer][:conn_status] == 0)

          if(counter % CONST[:timer][:reset_at] == 0)
            counter = 1 
            print '_'
          end
          $stdout.flush
          # hagyjunk teret, hátha...
          Thread.pass
        rescue Exception => e
           puts e.message
           puts "Backtrace:"
           e.backtrace.each {|line| puts line }
        end
      end
    end
  end

  # SkypeAPI console thread

  if MODE == :WithSkypeAPIConsole
   threads << Thread.new do
      begin
        sleep 1 until defined?(MyStore::SkypeR_Console)
        puts 'SkypeAPI console Thread running...'
        # MyStore::FRIENDS = MyStore::Rubi.retreive_friends_info
        # puts MyStore::FRIENDS
        MyStore::SkypeR_Console.input_loop
       rescue Exception => e
         puts e.message
         puts "Backtrace:"
         e.backtrace.each {|line| puts line }
      end
    end
  end

  RBus.mainloop

  threads.each{ |t| t.join }
rescue Exception => e
  #puts e.message
  #puts "Backtrace:"
  #e.backtrace.each {|line| puts line }

  reading_data = true
  threads.each{|t| Thread.kill(t) }
  MyStore::Rubi.exit
  MyStore::Logic.exit
  puts 'bye.'
end




