require 'net/http'

$SIGNATURE = [
  'yt-autoexpand',
  'Grzegorz Antoniak',
  '0.1',
  'BSD',
  'Autoexpand YouTube links',
  'weechat_unload',
  'UTF-8'
]

class TooManyRedirectsError < Exception
  def to_s
    "Too many redirects"
  end
end

class RequestError < Exception
  def to_s
    "HTTP request error"
  end
end

class YoutubeExpander
  def extract_link_from(message)
    if message =~ /.*((http|https):\/\/www\.youtube\.com\/.*) .*/i
      return $1.strip
    end

    if message =~ /.*((http|https):\/\/www\.youtube\.com\/.*)$/i
      return $1.strip
    end

    if message =~ /.*((http|https):\/\/youtu\.be\/.*?) .*/i
      return $1.strip
    end

    if message =~ /.*((http|https):\/\/youtu\.be\/.*?)$/i
      return $1.strip
    end

    return nil
  end
  def fetch(url, limit)
    raise TooManyRedirectsError if limit == 0

    uri = URI(url)
    req = Net::HTTP::Get.new "#{uri.path}?#{uri.query}", {
      'User-Agent' => 'WeeChat autoexpander/1.0'
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    resp = http.request req

    case resp
    when Net::HTTPSuccess then
      resp
    when Net::HTTPRedirection then
      return fetch(resp['location'], limit - 1)
    else
      raise RequestError
    end

    title = ""
    description = ""
    keywords = ""
    res = resp.read_body

    if res =~ /.*<title>(.*?)<\/title>.*/i
      title = $1.gsub "- YouTube", ""
      title.strip!
    end

    if res =~ /.*<meta name="description" content="(.*?)".*/i
      description = $1.strip
    end

    if res =~ /.*,"keywords":"(.*?)".*/i
      keywords = $1.strip.split(",").join ", "
    end

    {:title => title, :description => description, :keywords => keywords }
  end

  def expand(url)
    fetch(url, 2)
  rescue TooManyRedirectsError => e
    {:error => "Too many redirects"}
  rescue RequestError => e
    {:error => "HTTP error"}
  rescue URI::InvalidURIError => e
    {:error => "URI error"}
  end
end

def out(buf, msg)
  Weechat.print(buf, msg)
end

def fix(str)
  str.gsub("&amp;", "&")
      .gsub("\u0026", "&")
      .gsub("&lt;", "<")
      .gsub("&gt;", ">")
      .gsub("&quot;", "\"")
      .gsub("&dash;", "-")
      .gsub("&mdash;", "--")
      .gsub("&#39;", "\"")
end

def hook_print_cb(data, buffer, date, tags, displayed, highlight, prefix, message)
  yt = YoutubeExpander.new
  url = yt.extract_link_from message
  if url == nil
    return Weechat::WEECHAT_RC_OK
  end

  info = yt.expand(url)
  if info == nil
    out(buffer, "Error while autoexpanding this YouTube URL: #{url}")
    return Weechat::WEECHAT_RC_OK
  end

  title = fix(info[:title])
  description = fix(info[:description])
  keywords = fix(info[:keywords])

  c1 = Weechat.color("red,white")
  c2 = Weechat.color("white,red")
  cd = Weechat.color("reset")
  ctext = Weechat.color("darkgray")

  banner = "[#{c1}You#{c2}Tube#{cd}"
  if title != ""
    out(buffer, "#{banner} #{ctext}#{title}#{cd}]")
    out(buffer, "#{banner} desc: #{ctext}#{description}#{cd}]") unless description == ""
    out(buffer, "#{banner} tags: #{ctext}#{keywords}#{cd}]") unless keywords == ""
  else
    out(buffer, "YouTube auto-expansion failed for this URL!")
  end

  Weechat::WEECHAT_RC_OK
end

def weechat_init
  Weechat.register(*$SIGNATURE)
  Weechat.hook_print("", "notify_message", "://", 1, "hook_print_cb", "")
  Weechat.hook_print("", "notify_private", "://", 1, "hook_print_cb", "")
  Weechat.hook_print("", "notify_none",    "://", 1, "hook_print_cb", "")
  Weechat::WEECHAT_RC_OK
end

def weechat_unload
  Weechat::WEECHAT_RC_OK
end
