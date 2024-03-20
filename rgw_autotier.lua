--
-- S3 Object Auto-tiering Script for CephRGW
-- Copyright (c) 2024 OSNexus <info@osnexus.com>
-- Author: Steven Umbehocker
--
--  This library is free software; you can redistribute it and/or
--  modify it under the terms of the GNU Lesser General Public
--  License as published by the Free Software Foundation; either
--  version 2.1 of the License, or (at your option) any later version.
--
--

-- see https://docs.ceph.com/en/quincy/radosgw/lua-scripting/#request-fields for full 
-- list of Request fields and writable options.

-- see https://github.com/OSNEXUS/rgw-autotier for GitHub documentation on this script

patternsFilename = "/etc/ceph/rgw_autotier.prop"

local function fileExists(val)
  local fHandle = io.open(val, "r")
  if fHandle ~= nil then 
    io.close(fHandle)
    return true
  else
    return false 
  end
end

local function isInteger(val)
  if val == nil then return false end
  if tonumber(val, 10) == nil then return false end
  return true
end

local function isEmpty(val)
  return val == nil or val == ''
end

local function trim(val)
  return val:match( "^%s*(.-)%s*$" )
end

local function split(val)
  local result = {}
  local i = 1;
  for token in string.gmatch(val, "[^&;]+") do
    result[i] = trim(token)
    i = i+1
  end
  return result
end

local function startsWith(val, pat)
    return val:sub(1, #pat) == pat
end

-- exit early if this is not a S3 PUT or multipart upload operation
if Request.RGWOp ~= 'put_obj' and Request.RGWOp ~= 'complete_multipart' and Request.RGWOp ~= 'init_multipart' then
  -- RGWDebugLog("Not a auto-tierable S3 operation skipping auto-tiering: '" .. Request.RGWOp .. "' object " .. Request.Object.Name)
  return
end

-- exit early if the user has explicitly set the S3 StorageClass
if not isEmpty(Request.HTTP.StorageClass) then
  -- RGWDebugLog("StorageClass already specified, skipping auto-tiering.")
  return
end

-- exit early if the configuration file is not in place
if not fileExists(patternsFilename) then
  -- RGWDebugLog("Configuration file (" .. patternsFilename .. ") not detected, skipping auto-tiering.")
  return
end

-- exit early if we have no object information
if Request.Object == nil then
  -- RGWDebugLog("Object info unavailable, skipping auto-tiering.")
  return
end

patternsFile = io.open(patternsFilename, "r")
for line in patternsFile:lines() do

  tokens = {}
  tokens = split(line)

  -- RGWDebugLog("Processing storage class match rule: " .. line)
  if tokens ~= nil and #tokens >= 2 then
    
    storageClass = tokens[1]

    -- check if comment line
    if storageClass == '' or startsWith(storageClass, '--') or startsWith(storageClass, '#') then
      goto continue_gmatch
    end
    
    patternMatch = tokens[2]
    capacityThreshold = "0"
    operator = ""
    bucketMatch = ""
    tenantMatch = ""

    -- check for valid object size / content length matching params
    if #tokens >= 3 then
        operator = tokens[3]
        if #tokens >= 4 then
            capacityThreshold = tokens[4]
        end
    end

    -- check for valid bucket specifier
    if #tokens >= 5 then
        bucketMatch = tokens[5]
    end
    
    -- check for valid tenant specifier
    if #tokens >= 6 then
        tenantMatch = tokens[6]
    end

    -- RGWDebugLog("Processing tokens: storageClass '" .. storageClass .. "' patternMatch '" .. patternMatch .. "' operator '" .. operator .. "' capacityThreshold '" .. capacityThreshold .. "' bucketMatch '" .. bucketMatch .. "' tenantMatch '" .. tenantMatch .. "'")

    -- check for match to capacity threshold
    if operator ~= nil and operator ~= "" and operator ~= "*" and capacityThreshold ~= nil then
      if isInteger(capacityThreshold) then
        capacity = tonumber(capacityThreshold)
        if capacity > 0 then
          if operator == '>' and Request.ContentLength <= capacity then
            goto continue_gmatch
          elseif operator == '<' and Request.ContentLength >= capacity then
            goto continue_gmatch
          elseif operator == '>=' and Request.ContentLength < capacity then
            goto continue_gmatch
          elseif operator == '<=' and Request.ContentLength > capacity then
            goto continue_gmatch
          elseif operator == '=' and Request.ContentLength ~= capacity then
            goto continue_gmatch
          end
        end
      end
    end

    -- check for exact match to bucket name
    if bucketMatch ~= nil and bucketMatch ~= "" and bucketMatch ~= "*" then
        if bucketMatch ~= Request.Bucket.Name then
            goto continue_gmatch
        end
    end

    -- check for exact match to tenant name
    if tenantMatch ~= nil and tenantMatch ~= "" and tenantMatch ~= "*" then
        if tenantMatch ~= Request.Bucket.Tenant then
            goto continue_gmatch
        end
    end

    -- check for match to object name
    if patternMatch ~= nil and (patternMatch == "*" or string.find(Request.Object.Name, patternMatch)) then
      Request.HTTP.StorageClass = storageClass
      RGWDebugLog("  Object " .. Request.Object.Name .. " matched: storageClass '" .. storageClass .. "' patternMatch '" .. patternMatch .. "' operator '" .. operator .. "' capacityThreshold '" .. capacityThreshold .. "' bucketMatch '" .. bucketMatch .. "' tenantMatch '" .. tenantMatch .. "'")
      return
    end

    ::continue_gmatch::

  end
end

