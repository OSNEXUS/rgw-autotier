--
-- S3 Object Auto-tiering Script for CephRGW
-- Copyright (c) 2024 OSNexus <info@osnexus.com>
--
-- Author: Steven Umbehocker
--
--  This library is free software; you can redistribute it and/or
--  modify it under the terms of the GNU Lesser General Public
--  License as published by the Free Software Foundation; either
--  version 2.1 of the License, or (at your option) any later version.
--
--

-- Having problems? Start here to have it log and exit to make sure this Lua script loading and running.
--   RGWDebugLog("[S3 Object Auto-tiering Script for CephRGW]")
--   if true then return end

patternsFilename = "/etc/ceph/rgw_autotier.prop"

-- File format:
-- STORAGECLASS;PATTERN;OPERATOR;CAPACITY
-- 
-- STORAGECLASS must be a valid storage class associated with a Ceph bucket.data pool else
-- object PUT request will be rejected if the assigned STORAGECLASS is not valid/defined
--
-- PATTERN can be any pattern that can be put to Lua string.find() and should exclude semicolons (;)
--
-- OPERATOR can be greater-than '>', less-than '<', equals '=', or '*' any size
-- The OPERATOR field is only valid if a valid CAPACITY is specified
--
-- CAPACITY indicates the capacity in bytes to apply the OPERATOR to with the Request.ContentLength
-- For example if CAPACITY is 65536 and OPERATOR is < then only PUT requests of objects 
-- with Request.ContentLength less than 65536 will match.
--
-- Object name matching with PATTERN and capacity matching with OPERATOR+CAPACITY can be
-- used together or separately.  When not using any given field use the asterisk '*' to denote any/all match.

-- Example storage class pattern matching rules file:
----
-- # put all files less than 32K into INTELLIGENT_TIERING regardless of object name
-- INTELLIGENT_TIERING;*;<;32768
-- # put all .eml files into STANDARD_IA regardless of size
-- STANDARD_IA;.eml;*;*
-- # put all .pdf great then 1MiB into STANDARD storage class
-- STANDARD;.pdf;>;1048576
-- # put all .iso images less than 1GiB into the REDUCED_REDUNDANCY storage class
-- REDUCED_REDUNDANCY;.iso;>;1073741824
-- # put all .xlsx files less than 64K into STANDARD_IA
-- STANDARD_IA;.xlsx;<;65536
----

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

-- exit early if this is not a S3 PUT operation
if Request.RGWOp ~= 'put_obj' then
  -- RGWDebugLog("Not a S3 PUT operation, skipping auto-tiering.")
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

  -- RGWDebugLog("Processing storage class match rule: " .. line)

  for storageClass,patternMatch,operator,capacityThreshold in string.gmatch(line, "([^&;]+);([^&;]+);([^&;]+);([^&;]+)") do 

    -- check for valid storage class
    if storageClass == nil then 
      goto continue_gmatch
    end

    -- skip if empty or a comment line
    storageClass = string.gsub(storageClass, "%s+", "")
    if storageClass == '' or storageClass == '--' or storageClass == '#' then
      goto continue_gmatch
    end

    -- RGWDebugLog("Processing tokens: storageClass '" .. storageClass .. "' patternMatch '" .. patternMatch .. "' operator '" .. operator .. "' capacityThreshold '" .. capacityThreshold .. "'")

    -- check for match to capacity threshold
    if operator ~= nil and capacityThreshold ~= nil then
      operator = string.gsub(operator, "%s+", "")
      capacityThreshold = string.gsub(capacityThreshold, "%s+", "")
      if isInteger(capacityThreshold) then
        capacity = tonumber(capacityThreshold)
        if capacity > 0 then
          if operator == '>' and Request.ContentLength < capacity then
            goto continue_gmatch
          elseif operator == '<' and Request.ContentLength > capacity then
            goto continue_gmatch
          elseif operator == '=' and Request.ContentLength ~= capacity then
            goto continue_gmatch
          end
        end
      end
    end

    -- check for match to file name pattern
    patternMatch = string.gsub(patternMatch, "%s+", "")
    if patternMatch ~= nil and (patternMatch == "*" or string.find(Request.Object.Name, patternMatch)) then
      Request.HTTP.StorageClass = storageClass
      RGWDebugLog("  Object " .. Request.Object.Name .. " matched: storageClass '" .. storageClass .. "' patternMatch '" .. patternMatch .. "' operator '" .. operator .. "' capacityThreshold '" .. capacityThreshold .. "'")
      return
    end

    ::continue_gmatch::
  end
end

