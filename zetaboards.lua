dofile("urlcode.lua")
dofile("table_show.lua")

local item_type = os.getenv('item_type')
local item_value = string.lower(os.getenv('item_value'))
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local discovered_forums = {}
local discovered_forumpages = {}
local discovered_memberpages = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
     or string.match(url, "[<>\\{}]")
     or string.match(url, "//$")
     or string.match(url, "locale%.lang")
     or string.match(url, "subscribe$")
     or string.match(url, "/topic/[0-9]+")
     or string.match(url, "/profile/[0-9]+")
     or string.match(url, "/stats/list/%?tid=[0-9]+")
     or string.match(url, "/forum/[0-9]+/[0-9]+/$")
     or string.match(url, "/blog/main/[0-9]+/$")
     or string.match(url, "/blog/entry/[0-9]+/[0-9]+/$")
     or string.match(url, "/members/[0-9]+/") then
    return false
  end

  if string.match(url, "/calendar/bday/.+[^a-zA-Z]y=[0-9]+")
     and string.match(url, "[^a-zA-Z]y=([0-9]+)") ~= "2018" then
    return false
  end

  if string.match(url, "^https?://([^/]+)") == item_value then
    return true
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if item_type == "forumbase"
     and downloaded[url] ~= true and addedtolist[url] ~= true
     and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end

  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}

  if item_type == "forumids" then
    if not string.match(url, "^https?://[0-9]+%.a?[0-9]+%.zetaboards%.com/") then
      if string.match(url, "/index/?$") then
        forum = string.match(url, "^https?://(.+)/index/?$")
      else
        forum = string.match(url, "^https?://(.+)/")
      end
      print("Discovered forum " .. forum .. ".")
      discovered_forums[forum] = true
    end
    return urls
  end

  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(url, "&amp;", "&")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
       and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end

  local function extractpages(html)
    local pages = 1
    if string.match(html, "spawnJump") then
      pages = string.match(html, "spawnJump%(this,([0-9]+),[0-9]+,board_url%);")
    end
    return pages
  end

  if allowed(url, nil)
      and not string.match(url, "^https?://[^/]+/forum/[0-9]+/[0-9]") then
    html = read_file(file)

    if string.match(url, "/forum/[0-9]+/$") then
      local forumid = string.match(url, "/forum/([0-9]+)/$")
      local pages = extractpages(html)
      discovered_forumpages[item_value .. ":" .. forumid .. ":" .. pages] = true
    end

    if string.match(url, "/members/$") then
      discovered_memberpages[extractpages(html)] = true
    end

    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
       checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      check(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if item_type == "forumids"
         or allowed(url["url"], nil) or status_code == 500 then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local file = io.open(item_dir..'/'..warc_file_base..'_data.txt', 'w')
  if item_type == "forumids" then
    for website, _ in pairs(discovered_forums) do
      file:write("baseforum:" .. website .. "\n")
    end
  elseif item_type == "forumbase" then
    for data, _ in pairs(discovered_forumpages) do
      file:write("forumpages:" .. data .. "\n")
    end
    for data, _ in pairs(discovered_memberpages) do
      file:write("memberpages:" .. data .. "\n")
    end
  end
  file:close()
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
