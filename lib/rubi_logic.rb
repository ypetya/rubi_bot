#{{ Kiírjuk ha betöltődött a logika. ennek akkor van szerepe, ha újratölti futás közben!
puts "Rubi Logic loaded...(#{Time.now})"
#}}

class RubiLogic
  
  REPL = [Hash[*%w{Á A Í I Ű U Ő O Ü U Ö O Ú Ú Ó O É E á a í i ű u ő o ü u ö o ú u ó o é e}],
    Hash[*%w{\\xC3\\x81 A \\xC3\\x8D I \\xC5\\xB0 U \\xC5\\x90 O \\xC3\\x9C U \\xC3\\x96 O \\xC3\\x9A U \\xC3\\x93 O \\xC3\\x89 E \\xC3\\xA1 a \\xC3\\xAD i \\xC5\\xB1 u \\xC5\\x91 o \\xC3\\xBC u \\xC3\\xB6 o \\xC3\\xBA u \\xC3\\xB3 o \\xC3\\xA9 e}]]

  def ch8592_repl string
    REPL.each{|r| r.keys.each{|k| string.gsub!(/#{k}/,r[k])}}
    return string
  end
  # 1.
  # induláskor 1x fut le
  def start
    puts 'Cache: loading data from disk...'
    MyStore::Rubi.load_cache_from_filesystem MyStore::DATA_DIRECTORY
#    puts 'Loading All Chats and history... May take a while..'
#    MyStore::Rubi.get_all_chats.each{ |chat|
#      MyStore::Rubi.get_chat_history chat.id
#    }
    send_test_message
  end

  # 2.
  # ez történik amikor egy megváltozott chatablakról értesül (oda érkezett üzenet
  def enter_chat chat_id
    old_chat_topic = MyStore::Rubi.receive_chat_info(chat_id,'TOPIC')
    unless old_chat_topic =~ /- Rubi/
      new_chat = MyStore::Rubi.get_chat(chat_id,true)
      MyStore::Rubi.set_chat_topic(chat_id,new_chat.topic+ ' - Rubi')
      members = MyStore::Rubi.get_chatmembers(chat_id).map{|c| c.fullname}.join(', ')
      messages = "#{MyStore::Rubi.get_chat_history(chat_id).size.to_s} messages"
      MyStore::Rubi.send_chatmessage(chat_id,"##{members}:#{messages}.")
    end
  end

  # 3.
  # az enter_chat után megkapja az új üzeneteket
  def new_message message
      puts "\nNew message #{message.fromhandle} : #{message.body}"
      if message.fromhandle == 'ypetya'
        MyStore::Rubi.send_chatmessage(message.chatname,"#{MyStore::Rubi.get_chat_history(message.chatname,true).size.to_s} messages stored.") if message.body =~ /[#]\sload history/
        #MyStore::Rubi.send_chatmessage(message.chat, ch8592_repl(message.body).reverse)
      end
  end

  #4.
  # egyszer fut le a program futás végén
  def exit
    puts 'Leaving chats...'
    MyStore::Rubi.get_chats.each{|chat_id_sym,chat| leave_chat chat.id}
    puts 'Cache: Storing data to disk...'
    MyStore::Rubi.save_cache_to_filesystem MyStore::DATA_DIRECTORY
  end

  #5.
  # exit esemény hívja meg
  def leave_chat chat_id
    old_chat_topic = MyStore::Rubi.receive_chat_info(chat_id,'TOPIC')
    if old_chat_topic =~ /- Rubi/
      MyStore::Rubi.set_chat_topic(chat_id,old_chat_topic.gsub('- Rubi',''),true)
    end
  end
  #2 percenként figyeli, ezt hívja meg az eredménnyel.
  def new_userauthorizationrequest user
    puts "\nNew Authorized user: #{user}."
    MyStore::Rubi.set_user_isauthorized(user,true)

  end
end
