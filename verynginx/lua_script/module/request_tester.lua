-- -*- coding: utf-8 -*-
-- @Date    : 2016-02-06 22:26
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    : 
-- @Disc    : test a request hit a matcher or not

local cookie = require "cookie"

local _M = {}

local tester = {}

local json = require "json"
function _M.test( matcher )
    if matcher == nil then
        return false
    end
    -- matcher here is not the 'matcher' in config.json
	for name, v in pairs( matcher ) do
        --ngx.log(ngx.ERR, "name in matcher is:", name)
        --ngx.log(ngx.ERR, "v in matcher is:", json.encode(v))
        if tester[name] ~= nil then
            if tester[name]( v ) ~= true then
                return false
			end
		end
	end

	return true
end

--test_var is a basic test method, used by other test method 
function _M.test_var( match_operator, match_value, target_var )
    
   if match_operator == "=" then
        if target_var == match_value then
            return true
        end
    elseif match_operator == "*" then
        return true
    elseif match_operator == "!=" then
        if target_var ~= match_value then
            return true
        end
    elseif match_operator == '≈' then
        if type(target_var) == 'string' and ngx.re.find( target_var, match_value, 'isjo' ) ~= nil then
            return true
        end
    elseif match_operator == '!≈' then
        if type(target_var) ~= 'string' or ngx.re.find( target_var, match_value, 'isjo' ) == nil then
            return true
        end
    elseif match_operator == 'Exist' then
        if target_var ~= nil then
            return true
        end
    elseif match_operator == '!Exist' then
        if target_var == nil then
            return true
        end
    elseif match_operator == '!' then
        if target_var == nil then
            return true
        end
    end

    return false
end


--test a group of var in table with a condition 
function _M.test_many_var( var_table, condition )
    
    local test_var = _M.test_var

    local name_operator = condition['name_operator']
    local name_value = condition['name_value']
    local operator = condition['operator']
    local value = condition['value']

     -- Insert !Exist Check here as it is only applied to operator
    if operator == '!Exist' then
        for k, v in pairs(var_table) do
            if test_var ( name_operator, name_value, k ) == true then
                return false
            end
        end
        return true
    else
     -- Normal process
        for k, v in pairs(var_table) do
            if test_var( name_operator, name_value, k ) == true then
                if test_var( operator, value, v ) == true then -- if any one value match the condition, means the matcher has been hited 
                    return true 
                end
            end
        end
    end

    return false
end

function _M.test_uri( condition )
    local uri = ngx.var.uri;
    return _M.test_var( condition['operator'], condition['value'], uri )
end

function _M.test_ip( condition )
    local remote_addr = ngx.var.remote_addr
    return _M.test_var( condition['operator'], condition['value'], remote_addr )
end

function _M.test_ua( condition )
    local http_user_agent = ngx.var.http_user_agent;
    return _M.test_var( condition['operator'], condition['value'], http_user_agent )
end

function _M.test_referer( condition )
    local http_referer = ngx.var.http_referer;
    return _M.test_var( condition['operator'], condition['value'], http_referer )
end

--uncompleted
function _M.test_method( condition )
    local method_name = ngx.req.get_method()
    return _M.test_var( condition['operator'], condition['value'], method_name )
end

function _M.test_args( condition )
    local find = ngx.re.find
    local test_var = _M.test_var

    --ngx.log( ngx.ERR, "in test_args, condition:", json.encode(condition) )
    --old version value is one string
    if condition[1] == nil then
        --这里是老板condition，类型是字典，直接把键和值读出来
        --ngx.log(ngx.ERR, "\nenter ONE arg test")
        local name_operator = condition['name_operator']
        local name_value = condition['name_value']
        local operator = condition['operator']
        local value = condition['value']
        --ngx.log(ngx.ERR, "ONE ARG is: ", value)
        --handle args behind uri
        for k,v in pairs( ngx.req.get_uri_args()) do
            --参数名对的上
            --ngx.log(ngx.ERR, json.encode(v))
            ngx.log(ngx.ERR, "k in ngx.req.get_uri_args():", json.encode(k))
            ngx.log(ngx.ERR, "v in ngx.req.get_uri_args():", json.encode(v))
            if test_var( name_operator, name_value, k ) == true then
                --当url中对同一参数名指定不同参数值时，两个参数值组成table。
                if type(v) == "table" then
                    for arg_idx,arg_value in ipairs(v) do
                        --参数值对的上
                        if test_var( operator, value, arg_value ) == true then 
                            return true
                        end
                    end
                else
                    if test_var( operator, value, v ) == true then
                        return true
                    end
                end
            end
        end
        ngx.req.read_body()
        --ensure body has not be cached into temp file
        if ngx.req.get_body_file() ~= nil then
            return false
        end
        local body_args,err = ngx.req.get_post_args()
        if body_args == nil then
            ngx.say("failed to get post args: ", err)
            return false
        end
        --check args in body
        for k,v in pairs( body_args ) do
            if test_var( name_operator, name_value, k ) == true then
                if type(v) == "table" then
                    for arg_idx,arg_value in ipairs(v) do
                        if test_var( operator, value, arg_value ) == true then 
                            return true
                        end
                    end
                else
                    if test_var( operator, value, v ) == true then
                        return true
                    end
                end
            end
        end
        return false
    --如果需要匹配多个参数
    elseif type( condition[1] ) == "table" then
        --ngx.log(ngx.ERR, '\nenter table test')
        --总共应该匹配count条规则
        local count = #condition
        for ck,cv in pairs(condition) do
            local name_operator = cv['name_operator']
            local name_value = cv['name_value']
            local operator = cv['operator']
            local value = cv['value']
            --ngx.log(ngx.ERR, name_operator..'\t'..name_value..'\t'..operator..'\t'..value)
            --#region
            --对于url中的每一个参数
            for k,v in pairs( ngx.req.get_uri_args()) do
                --ngx.log(ngx.ERR, json.encode(v))
                --ngx.log(ngx.ERR, "v in ngx.req.get_uri_args():", json.encode(v))
                --参数名对的上
                if test_var( name_operator, name_value, k ) == true then
                    --当url中对同一参数名指定不同参数值时，两个参数值组成table。
                    if type(v) == "table" then
                        for arg_idx,arg_value in ipairs(v) do
                            --参数值对不上
                            if test_var( operator, value, arg_value ) == true then
                                --return false
                                count = count - 1
                            end
                        end
                    else
                        if test_var( operator, value, v ) == true then
                            --return false
                            count = count - 1
                        end
                    end
                end
            end
            ngx.req.read_body()
            --ensure body has not be cached into temp file
            if ngx.req.get_body_file() ~= nil then
                return false
            end

            local body_args,err = ngx.req.get_post_args()
            if body_args == nil then
                ngx.say("failed to get post args: ", err)
                return false
            end

            --check args in body
            for k,v in pairs( body_args ) do
                --参数名
                if test_var( name_operator, name_value, k ) == true then
                    if type(v) == "table" then
                        for arg_idx,arg_value in ipairs(v) do
                            if test_var( operator, value, arg_value ) == true then 
                                --return false
                                count = count - 1
                            end
                        end
                    else
                        if test_var( operator, value, v ) == true then
                            --return false
                            count = count - 1
                        end
                    end
                end
            end
            --#region
        end
        return count <= 0
    else
        return false
    end
end

function _M.test_host( condition )
    local hostname = ngx.var.host
    return _M.test_var( condition['operator'], condition['value'], hostname )
end

function _M.test_header( condition )
    local header_table = ngx.req.get_headers()
    return _M.test_many_var( header_table, condition )
end

function _M.test_cookie( condition )
    local cookie_obj, err = cookie:new()
    local cookie_table = cookie_obj:get_all()

    if cookie_table == nil then
        cookie_table = {}
    end
    return _M.test_many_var( cookie_table, condition )
end

tester["URI"] = _M.test_uri
tester["IP"] = _M.test_ip
tester["UserAgent"] = _M.test_ua
tester["Method"] = _M.test_method
tester["Args"] = _M.test_args
tester["Referer"] = _M.test_referer
tester["Host"] = _M.test_host
tester["Header"] = _M.test_header
tester["Cookie"] = _M.test_cookie


return _M
