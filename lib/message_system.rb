require 'yaml'

SELF_NAME = 'rubi_bot'

require 'lib/object_cache.rb'


class MessageSystem

  def save_cache_to_filesystem directory
    @cache.store_to_dir directory
  end

  def load_cache_from_filesystem directory
    @cache.load_from_dir directory
  end

  def initialize
    @friends,@missedchats,@recentchatmessages = [],[],[]
    @cache = Cache.new
    @verbose = false
    @message_counter = 0
    @log_char = "_"
    @debug = DEBUG
  end

  def get_chatmessages
    return @cache.chatmessages || {}
  end

  def exit
    get_chatmessages.each{ |k,m|
      @cache.set_chatmessage_status(k,'READ') if m.status == 'RECEIVED';
    }
  end
  
  def delay_message
      @message_counter += 1
      return @log_char if @debug == true
      return '.'
  end

  def get_answer command
    print(delay_message)
    $stdout.flush
    command_message = SkypeR::Service::CommandMessage.new(command)
    #puts command_message.inspect
    SkypeR::SKYPE.send('parse',command_message)
    return SkypeR::SKYPE.invoke( command_message, 60)
  end

  def return_array string_with_main_element, first_element_index = 2, options = {}
    string_to_process = string_with_main_element || ''
    array_to_process = string_to_process.split.map{|e| e.gsub(/,/,'')}
    return array_to_process[(first_element_index)..(array_to_process.length-1)] if array_to_process.length > first_element_index
    nil
  rescue
    []
  end
  alias :get_array :return_array

  def return_at string,index = 1
    return nil if string == nil
    my_arr = string.split
    return my_arr[index] if index < my_arr.length
    ''
  end

  # returns friend list
  def receive_friends
    @log_char = "sF"
    if return_val = return_array(get_answer('SEARCH FRIENDS'))
      return @friends = return_val
    else
      return @friends = [] unless @friends
    end
    @friends
  end

  #returns missed chat id-s
  #storeing answer
  def receive_missed_chats
    @log_char = "MC"
    if return_val = return_array(get_answer('SEARCH MISSEDCHATS'))
      return @missedchats = return_val
    else
      return @missedchats = [] unless @missedchats
    end
    @missedchats
  end

  #returns all chats
  def receive_all_chats
    @log_char = "SC"
    return return_array(get_answer('SEARCH CHATS')) || []
  end

  #returns chat id-s
  def receive_recentchatmessages(chat_id)
    @log_char = "Cr"
    if return_val = get_array(get_answer("GET CHAT #{chat_id} RECENTCHATMESSAGES"), 4)
      return @recentchatmessages = return_val
    else
      return @recentchatmessages = [] unless @recentchatmessages
    end
    @recentchatmessages
  end

  def receive_chat_members(chat_id)
    @log_char = "CM"
    if return_arr = get_array(get_answer("GET CHAT #{chat_id} MEMBERS"),4)
      return return_arr
    else
      return []
    end
  end

  def receive_chatmessages(chat_id)
    @log_char = "Cm"
    get_array(get_answer("GET CHAT #{chat_id} CHATMESSAGES"),4) || []
  end

  def receive_missedchatmessages
    @log_char = 'Mm'
    mm = (return_array(get_answer('SEARCH MISSEDCHATMESSAGES')) || []).map{|msg_id| get_chatmessage(msg_id,nil,true)}
    mm_2 = mm#.select{|msg| msg.status == 'RECEIVED' }
    mm_2.each{|c| 
      set_chatmessage_status(c.chatname, c.id.gsub(/#[^#]*?#/,''), 'SEEN')}
      
    return mm_2.reverse    
  end
  alias :missed_chatmessages :receive_missedchatmessages

  def receive_user_info(id,prop)
    @log_char = "Up"
    if return_arr = get_array( get_answer("GET USER #{id} #{prop}"),4)
      return return_arr.join(' ')
    else
      return ''
    end
  end

  def receive_chat_info(id,prop)
    return unless id =~ /#(.*?);(.*?)/

    @log_char = "Cp"
    if return_arr = get_array( get_answer("GET CHAT #{id} #{prop}"),4)
      return return_arr.join(' ')
    else
      return ''
    end
  end

  def receive_chatmessage_info(id,prop)
    @log_char = "mp"
    if return_arr = get_array( get_answer("GET CHATMESSAGE #{id} #{prop}"),4)
      return return_arr.join(' ')
    else
      return ''
    end
  end

  def receive_userswaitingmyauthorization
    @log_char = "Ua"
    if return_arr = get_array(get_answer("SEARCH USERSWAITINGMYAUTHORIZATION"),2)
      return return_arr
    else
      return []
    end
  end

  # egyedi chat üzenet azonosító a cache-ben. a chat_id-ból képződik
  # a chatmessage_id-k ismétlődhetnek!
  def u_cm_id chat_id,chatmessage_id
    "#{chat_id}##{chatmessage_id}"
  end

  #returns message status string
  def get_chatmessage_status c_id, cm_id, force = false
    @log_char = "cs"
    return @cache.get_chatmessage_status(u_cm_id(c_id,cm_id)) if @cache.get_chatmessage_status(u_cm_id(c_id,cm_id)) and not force
    if return_val = return_at(get_answer("GET CHATMESSAGE #{cm_id} STATUS"),4)
      return @cache.set_chatmessage_status(u_cm_id(c_id,cm_id), return_val)
    end
    return ''
  end

  def set_chatmessage_status c_id, cm_id, status
    @log_char = "cS"
    @cache.set_chatmessage_status(u_cm_id(c_id,cm_id), status)
    get_answer("SET CHATMESSAGE #{cm_id} #{status}")
  end

  def set_user_isblocked(user_id,block = true)
    @log_char = "UB"
    get_answer("SET USER #{user_id} ISBLOCKED #{block ? 'TRUE' : 'FALSE'}")
  end

  def set_user_isauthorized user_id, authorized = true
    @log_char = "UA"
    get_answer("SET USER #{user_id} ISAUTHORIZED #{authorized ? 'TRUE' : 'FALSE'}")
  end

  #returns message body string
  def get_chatmessage_body c_id, cm_id
    @log_char = "mb"
    return @cache.get_chatmessage_body(u_cm_id(c_id,cm_id)) if @cache.get_chatmessage_body(u_cm_id(c_id,cm_id))
    if body = return_array(get_answer("GET CHATMESSAGE #{cm_id} BODY"),4)
      return @cache.set_chatmessage_body(u_cm_id(c_id,cm_id),body.join(' ')) if body.length > 0
    end
    return ''
  rescue
    return ''
  end

  #CHATNAME = CHAT_ID !
  def get_chatmessage_info cm_id,c_id=nil, force = false
    if c_id == nil
      c_id = receive_chatmessage_info(cm_id,'CHATNAME')
    end
    @cache.set_chatmessage_chatname(u_cm_id(c_id,cm_id),c_id)
    %w{STATUS BODY TYPE FROMHANDLE}.each{|prop|
     
     if not @cache.send("get_chatmessage_#{prop.downcase}".to_sym,u_cm_id(c_id,cm_id)) or force
       @cache.send("set_chatmessage_#{prop.downcase}".to_sym, u_cm_id(c_id,cm_id),
         receive_chatmessage_info(cm_id, prop == 'FROMHANDLE' ? 'FROM_HANDLE': prop ))
     end
    }
    @cache.get_chatmessage(u_cm_id(c_id,cm_id))
  end
  alias :get_chatmessage :get_chatmessage_info

  #receives specified user properties from skype and stores to cache
  def retreive_user_info u_id, force = false
    %w{FULLNAME SEX BIRTHDAY CITY}.each{|prop|
      if not(@cache.send("get_user_#{prop.downcase}".to_sym,u_id)) or force == true
        @cache.send("set_user_#{prop.downcase}".to_sym, u_id,
          receive_user_info(u_id,prop))
      end
    }
  end

  #retreives info to cache
  def retreive_friends_info force = false
    @friends = [] if force
    receive_friends if @friends.empty?
    @friends.each{ |i| retreive_user_info(i,force)}
  end

  #retreives info to cache
  def retreive_chat_info id,force = false
    return unless id =~ /#(.*?);(.*?)/
    %w{MEMBERS FRIENDLYNAME TOPIC}.each{|prop| #CHATMESSAGES - not supported-yet
      if not(@cache.send("get_chat_#{prop.downcase}".to_sym,id)) or force
        @cache.send("set_chat_#{prop.downcase}".to_sym, id,
          receive_chat_info(id,prop))
      end
    }
  end

  #retreives missed chats and other chat parameters if it is not known already from cache
  def retreive_missed_chats force = false
    missed_ids = receive_missed_chats
    missed_ids.each { |chat_id| retreive_chat_info chat_id,force }
    return missed_ids
  end

  def retreive_all_chats force = false
    if force
      chats = receive_all_chats
    else
      chats = @cache.chats.map{|c| c.id}
    end
    chats.each{|chat_id| retreive_chat_info chat_id }
    return chats.map{|chat_id| @cache.get_chat chat_id}
  end

  def get_all_chats force = false
    chats = retreive_all_chats(true) if force || !(chats = @cache.chats)
    return chats
  end

  def get_chat_history chat_id,force = false
    if force || !(chatmessages = @cache.get_chat_chatmessages(chat_id))
      chatmessages = receive_chatmessages(chat_id)
      @cache.set_chat_chatmessages chat_id,chatmessages if chatmessages
    end
    return chatmessages.map{ |message_id|

      get_chatmessage message_id,chat_id
    }
  end

  def retreive_chatmembers chat_id,force = false
    ret_arr = []
    retreive_chat_info chat_id,force
    mem = @cache.get_chat(chat_id).members
    #puts "#{mem.inspect}"
    mem.split.each{ |member|
      retreive_user_info member
      ret_arr << @cache.get_user(member)
    }
    return ret_arr
  end
  alias :get_chatmembers :retreive_chatmembers

  def get_missed_chats
    retreive_missed_chats.map{|chat_id| @cache.get_chat(chat_id)}    
  end

  def get_chat(c_id,force=false)
    retreive_chat_info(c_id,force)
    return @cache.get_chat(c_id)
  end

  def set_chat_topic(c_id,new_topic,force=false)
    retreive_chat_info(c_id,force)
    @log_char = "CT"
    get_answer("ALTER CHAT #{c_id} SETTOPIC #{new_topic.strip}")
  end

  def get_user(id)
    retreive_user_info(id)
    return @cache.get_user(id)
  end

  #returns chats from cache (there was an event while bot online)
  def get_chats
    return @cache.chats || {}
  end

  def get_users
    return @cache.users || {}
  end
  
  #returns missed RECEIVED chatmessages.body in array
  def received_messages c_id, set_seen = false
    puts "getting missed messages ..." if @verbose
    message_ids = receive_recentchatmessages(c_id)
    puts "missed message_ids: #{message_ids.join(',')}" if @verbose

    return_arr = []
    message_ids.each do |m_id|
      next if @cache.get_chatmessage_status(c_id,m_id)
      status = get_chatmessage_status(c_id,m_id)

      puts "message(#{u_cm_id(c_id,m_id)}) STATUS: #{status} " if @verbose
      if status =~ /RECEIVED|SENT|SENDING/
        body = get_chatmessage_body(c_id,m_id)
        puts "message(#{u_cm_id(c_id,m_id)}) BODY: #{body}" if @verbose
        set_chatmessage_status(c_id, m_id, 'SEEN') if set_seen
        return_arr << body if status == 'RECEIVED'
      end
    end
    puts "processing missed messages finished." if @verbose
    return return_arr
  end

  #returns missed RECEIVED chatmessages
  def received_chatmessages c_id, set_seen = true, force = false
    message_ids = receive_recentchatmessages(c_id)
    return_arr = []
    message_ids.each do |cm_id|
      next if @cache.get_chatmessage_status(u_cm_id(c_id, cm_id)) and force == false
      status = get_chatmessage_status(c_id, cm_id, true)
      if (status =~ /RECEIVED|SENT|SENDING/) or force == true
        obj = get_chatmessage(cm_id, c_id, force)
        set_chatmessage_status(c_id, cm_id,'SEEN') if set_seen == true
        return_arr << obj if status == 'RECEIVED'
      end
    end
    return return_arr
  end

  def authorize_waiting_users
    receive_userswaitingmyauthorization.each{ |user| set_user_isauthorized(user) }
  end


  def send_chatmessage chat_id, message
    return if message.length > 512
    @log_char = "mM"
    return_at(get_answer("CHATMESSAGE #{chat_id} #{message}"),4)
  end

  #itt a lényeg, async üzenetkezelés
  def get_async_chats(&block)
    chat_id = nil
    Thread.exclusive(){ chat_id = SkypeR::SKYPE.missed_chats.delete_at(0)}
    return nil unless chat_id
#    chat = get_chat(chat_id)
    yield chat_id
    true
  rescue Exception => e
    puts e.message
    e.backtrace.each {|line| puts line }
  end

  def get_async_messages(&block)
    message_id = nil
    Thread.exclusive(){ message_id = SkypeR::SKYPE.missed_messages.delete_at(0)}
    return nil unless message_id
    msg = get_chatmessage(message_id)
    set_chatmessage_status(msg.chatname, message_id,'SEEN')
    yield(msg)
    true
  rescue Exception => e
    puts e.message
    e.backtrace.each {|line| puts line }
  end

  def status_changed(&block)
    status = nil
    Thread.exclusive(){ status = SkypeR::SKYPE.connstatus.delete_at(0)}
    return unless status
    yield(status)
  rescue Exception => e
    puts e.message
    e.backtrace.each {|line| puts line }
  end

end
