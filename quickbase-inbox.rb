
require 'sinatra'
require 'rack/ssl-enforcer'
require 'haml'
require 'yaml'
require 'quickbase_client'
require 'gmail_sender'

CONFIG = "config.yml"
APP = "QuickBase Email Inbox"
TABLE = "Emails"
FROM = "From"
TO = "To"
SUBJECT = "Subject"
MESSAGE = "Message"

configure do
  config = {}
  config = YAML.load_file(CONFIG)
  config.each{|k,v| config[k] = ENV[k.to_s] if ENV[k.to_s]}
  config.each{|k,v| set k.to_sym, v }
  if settings.environment == :production
    use Rack::SslEnforcer
  end
end

not_found do
  redirect  '/not_found.html'
end

get '/' do
  redirect '/home.html'
end

post '/:quickbase_username/:quickbase_password/:quickbase_realm/:dbid/:apptoken/:from_fid/:to_fid/:subject_fid/:message_fid' do
  begin
    quickbase_username = param?(params,:quickbase_username) || settings.quickbase_username
    quickbase_password = param?(params,:quickbase_password) || settings.quickbase_password
    quickbase_realm = param?(params,:quickbase_realm) || settings.quickbase_realm
    if quickbase_username and quickbase_password
      qbc = get_qbc(quickbase_username,quickbase_password,quickbase_realm)
      if qbc
        inbox_table = nil
        dbid = param?(params,:dbid) || settings.dbid
        if dbid
          inbox_table = get_inbox_table(qbc,dbid,params)
        else
          app_dbid = qbc.findDBByName(APP)
          if qbc.requestSucceeded and app_dbid
            dbid = qbc.lookupChdbid(TABLE,app_dbid)
            if dbid
              inbox_table = get_inbox_table(qbc,dbid,params)
            else
              puts "Unable to find #{TABLE} table in #{APP} application."
            end
          else
            inbox_table = create_inbox_table(qbc)
          end
        end
        if inbox_table
          qbc.addFieldValuePair(nil,inbox_table[:from_fid],nil,params["from"]) if inbox_table[:from_fid] and params["from"]
          qbc.addFieldValuePair(nil,inbox_table[:to_fid],nil,params["to"]) if inbox_table[:to_fid] and params["to"]
          qbc.addFieldValuePair(nil,inbox_table[:subject_fid],nil,params["subject"]) if inbox_table[:subject_fid] and params["subject"]
          qbc.addFieldValuePair(nil,inbox_table[:message_fid],nil,params["plain"]) if inbox_table[:message_fid] and params["plain"]
          qbc.addRecord(inbox_table[:dbid],qbc.fvlist)
        else
          puts "Unable to find or create Inbox table."
        end
      end
    end
  rescue StandardError => error
    puts "Error processing email message: #{error}"
  end
end

post '/request_info' do
  if params[:info_request_email].length > 0 and params[:info_request_message].length > 0
    if email_info_request(params[:info_request_email],params[:info_request_message],request.host)
      @request_info_text = "Your request for information has been submitted."
    else
      @request_info_text = "Oops! Something went wrong while your message was being submitted - sorry."
    end
  else
    @request_info_text = "Sorry - please enter your email address a message."
  end
  haml :request_info
end

private

def create_inbox_table(qbc)
  inbox_table = nil
  dummy, app_dbid = qbc.createDatabase(APP,APP)
  if qbc.requestSucceeded and app_dbid
    dbid = qbc.createTable(TABLE,TABLE,app_dbid)
    if qbc.requestSucceeded and dbid
      inbox_table = {}
      inbox_table[:dbid] = dbid
      inbox_table[:from_fid], dummy = qbc.addField(dbid,FROM,"email")
      inbox_table[:to_fid], dummy = qbc.addField(dbid,TO,"text") if qbc.requestSucceeded
      inbox_table[:subject_fid], dummy = qbc.addField(dbid,SUBJECT,"text") if qbc.requestSucceeded
      inbox_table[:message_fid], dummy = qbc.addField(dbid,MESSAGE,"text") if qbc.requestSucceeded
      if qbc.requestSucceeded
        qbc.setFieldProperties(dbid,{"num_lines" => "10"},inbox_table[:message_fid])
      else
        puts "Error creating field: #{qbc.lastError}"
      end 
    else
      puts "Error creating #{TABLE} table: #{qbc.lastError}"
    end
  else
    puts "Error creating #{APP} application: #{qbc.lastError}"
  end
  inbox_table
end

def get_inbox_table(qbc,dbid,params)
  inbox_table = nil
  qbc.getSchema(dbid)
  if qbc.requestSucceeded
    inbox_table = {}
    inbox_table[:dbid] = dbid
    inbox_table[:from_fid] = param?(params,:from_fid) || qbc.lookupFieldIDByName(FROM,dbid)
    inbox_table[:to_fid] = param?(params,:to_fid) || qbc.lookupFieldIDByName(TO,dbid)
    inbox_table[:subject_fid] = param?(params,:subject_fid) || qbc.lookupFieldIDByName(SUBJECT,dbid)
    inbox_table[:message_fid] = param?(params,:message_fid) || qbc.lookupFieldIDByName(MESSAGE,dbid)
  else
    puts "Error retrieving QuickBase schema for Inbox table #{dbid}: #{qbc.lastError}"
  end
  inbox_table
end

def param?(params,sym)
  params[sym] = nil if params[sym] and params[sym] == "-"
  params[sym]
end

def get_qbc(quickbase_username,quickbase_password,quickbase_realm)
  options = {"username" => quickbase_username, "password" => quickbase_password, "org" => quickbase_realm}
  qbc = QuickBase::Client.init(options)
  qbc.cacheSchemas=true
  qbc
end

def email_info_request(from,body,host)
  ret = true
  begin
    gms = GmailSender.new(settings.gmail_username, settings.gmail_password)
    gms.send({ :to => settings.gmail_username, :subject => "Request for info from #{from} on #{host}", :content => body})
  rescue StandardError => error
    puts "Error sending email: #{error}"
    ret = false
  end
  ret
end

__END__

@@ request_info
%html<
  %head<
    %title
      QuickBase Inbox - Request for Information
    %link{ :rel => "stylesheet", :href => "/site.css", :type => "text/css"}
  %body<
    %h2
      %a{ :href => "/home.html" }
        QuickBase Inbox
    %center
      %h3
        #{@request_info_text}
      %hr
