--[[
version=20
author=Liam Collod
last_modified=12/03/2022

Annotate (& color) lights in the viewer using their attributes.

OpScript for Foundry's Katana software

[OpScript setup]
  parameters:
    location:  /root/world/lgt//*{@type=="light"}
    applyWhere: at locations matching CEL
  user(type)(default_value):
    user.annotation_colored(bool)(true): true to colro the annotation in the viewer
    user.lights_colored(bool)(true): true to color the light in the viewer
    user.annotation_template(str)("<name>"): Use tokens to build the annotation for each light.
       tokens are defined in Light.tokens and are surrounded with <>
    user.color_hue(float)(1): 0-1 range
    user.color_saturation(float)(1): 0-1 range
    user.color_value(float)(1): 0-1 range

[License]
Copyright 2022 Liam Collod

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

]]


--[[ __________________________________________________________________________
  LUA UTILITIES
]]

local split
local round
local table2string
local stringify
local err
local color_gamma
local get_user_attr

err = function (...)
  --[[
  Raise an error.
  Concat the given arguments to string and pass them as the error's message.
  ]]

  local buf = {"[LgVA]["}
  buf[ #buf + 1 ] = Interface.GetInputLocationPath()
  buf[ #buf + 1 ] = "]"

  for i=1, select("#",...) do
    buf[ #buf + 1 ] = tostring(select(i,...))
  end

  error(table.concat(buf))

end


split = function(str, sep)
  --[[
  Source: https://stackoverflow.com/a/25449599/13806195
  ]]
  local result = {}
  local regex = ("([^%s]+)"):format(sep)
  for each in str:gmatch(regex) do
     table.insert(result, each)
  end
  return result
end


round = function(num, numDecimalPlaces)
  -- Source: http://lua-users.org/wiki/SimpleRound
  -- Returns: number
  return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end


table2string = function(tablevalue)
    --[[
  Convert a table to a one line string.
  If the key is a number, only the value is kept.
  If the key is something else, it is formatted to "tostring(key)=tostring(value),"

  Parameters:
    tablevalue(table): table to convert to string

  Returns:
    str:
  ]]

  local outtable = {"{"}
  local ctable = {} -- to avoid string concatenation in loop

  for k, v in pairs(tablevalue) do
    -- to avoid string concatenation in loop
    if (type(k) == "number") then
      table.insert(outtable, stringify(v)..", ")
    else
      ctable[1] = stringify(k)
      ctable[2] = "="
      ctable[3] = stringify(v)
      ctable[4] = ", "
      table.insert(outtable,tostring(table.concat(ctable)))
    end
  end

  table.insert(outtable, "}")

  return table.concat(outtable)

end


stringify = function(source)
  --[[
  Convert the source to a readable string , based on it's type.
  All numbers are rounded to 3 decimals.
  ]]
  if not source then
    return ""
  end

  local number_round = 3  -- number of decimals to keep.

  if (type(source) == "table") then
    if #source == 1 then
      return stringify(source[1])
    end
    source = table2string(source)

  elseif (type(source) == "number") then
    source = tostring(round(source, number_round))

  else
    source = tostring(source)

  end

  return source

end


get_user_attr = function(name, default_value)
    --[[
    Return an OpScipt user attribute.
    If not found return the default_value.
    ! The user attribute must not be an array of value else only the first item
    is returned.

    Args:
        name(str): attribute location (don't need the <user.>
        default_value(any): value to return if user attr not found
    Returns:
        type depends of input
    ]]
    local argvalue = Interface.GetOpArg("user."..name)
    if argvalue then
        return argvalue:getValue()
    else
      return default_value
    end

end


local function hsv(color, h, s, v)
  --[[
  Credit <colour-science> and <Easyrgb>.

  Args:
    color(table): r, g and b channel as a table
    h(num): hue ; 0-1 range; 1 for no effect
    s(num): saturation; 0-1 range; 1 for no effect
    v(num): value; 0-1 range; 1 for no effect
  ]]

  local r = color[1]
  local g = color[2]
  local b = color[3]

  -- 1. RGB to HSV
  local ch
  local cs
  local cv

  local d1
  local da
  local db
  local dc

  local hx

  cv = math.max(r,g,b)
  d1 = cv - math.min(r,g,b)  -- delta

  cs = d1 / cv
  if d1 == 0 then
    cs = 0
  end

  da = (((cv - r) / 6) + (d1 / 2)) / d1
  db = (((cv - g) / 6) + (d1 / 2)) / d1
  dc = (((cv - b) / 6) + (d1 / 2)) / d1

  ch = dc - db
  if g == cv then
    ch = (1 / 3) + da - dc
  end
  if b == cv then
    ch = (2 / 3) + db - da
  end
  if ch < 0 then
    ch = ch + 1
  end
  if ch > 1 then
    ch = ch - 1
  end
  if d1 == 0 then
    ch = 0
  end

  -- 2. Apply per-channel modification
  ch = ch * h
  cs = cs * s
  cv = cv * v

  -- 3. HSV to RGB
  hx = ch * 6
  if hx == 6 then
    hx = 0
  end

  d1 = math.floor(hx)
  da = cv * (1 - cs)
  db = cv * (1 - cs * (hx - d1))
  dc = cv * (1 - cs * (1-(hx - d1)))

  if d1 == 0 then
    r = cv
    g = dc
    b = da
  elseif d1 == 1 then
    r = db
    g = cv
    b = da
  elseif d1 == 2 then
    r = da
    g = cv
    b = dc
  elseif d1 == 3 then
    r = da
    g = db
    b = cv
  elseif d1 == 4 then
    r = dc
    g = da
    b = cv
  else
    r = cv
    g = da
    b = db
  end

  return { r, g, b }

end


--[[ __________________________________________________________________________
  API
]]

local function get_light_renderer()
  --[[
  From the currently visited light location, return which render-engine it
   was build for.

  Raise an error if the renderer can't be found.

  Returns:
    str: ai, dl, prman
  ]]

  local mat = Interface.GetAttr("material")
  -- the shader name should always be the first Group index 0
  if string.find(mat:getChildName(0), "arnold") then
    return "ai"
  elseif string.find(mat:getChildName(0), "dl") then
    return "dl"
  elseif string.find(mat:getChildName(0), "prman") then
    return "prman"
  else
    err("[get_light_renderer] Can't find a render engine for this light !")
  end

end

-- scene graph location of the current light visited
local LOCATION = Interface.GetInputLocationPath()
local RENDERER = get_light_renderer()


local function get_light_attr(attrs_list, default_value)
--[[
  Args:
      attrs_list(table of str):
        numerical table of attributes path.
        Function return at the first attribute to return a value.
      default_value(any):
        value to return if all attributes return nothing, pass <error> to raise
        an error instead.

  Returns:
      type depends of input
  ]]

  for i=1, #attrs_list do

    local attr = Interface.GetAttr(attrs_list[i])
    if attr then
      return attr:getNearestSample(0)
    end

  end

  if default_value==error then
    err(
      "[get_light_attr] No attribute found from",
      stringify(attrs_list)
    )
  else
    return default_value
  end

end


local function get_light_name()
  --[[
  Returns:
    str: name of the light based on its scene graph location.
  ]]
  local name = split(LOCATION, "/")
  return name[#name]  -- return the last element of the list
end

--[[
Light table object

the <tokens> key hold all the supported tokens.
- Each token key hold render-engine keys
  - each render-engine key hold a table with a <func> and a <params> key.

the default value for <get_light_attr> <params> is returned if the attribute
is not set locally (not modified)
]]
local Light = {

  ["tokens"] = {

    ["name"] = {
      ["ai"] = { func = get_light_name},
      ["dl"] = { func = get_light_name},
      ["prman"] = { func = get_light_name}
    },

    ["aov"] = {
      ["ai"] = {
        func = get_light_attr,
        params = { { "material.arnoldLightParams.aov" }, "default"},
      },
      ["dl"] = {},
      ["prman"] = {
        func = get_light_attr,
        params = { { "material.prmanLightParams.lightGroup" }, "none"},
      },
    },

    ["color"] = {
      ["ai"] = {
        func = get_light_attr,
        params = { { "material.arnoldLightParams.color" }, {1,1,1}},
      },
      ["dl"] = {
        func = get_light_attr,
        params = { { "material.dlLightParams.color" }, {1,1,1}},
      },
      ["prman"] = {
        func = get_light_attr,
        params = { { "material.prmanLightParams.lightColor" }, {1,1,1}},
      },
    },

    ["samples"] = {
      ["ai"] = {
        func = get_light_attr,
        params = { { "material.arnoldLightParams.samples" }, 1},
      },
      ["dl"] = {},
      ["prman"] = {
        func = get_light_attr,
        params = { { "material.prmanLightParams.fixedSampleCount" }, 0},
      },
    },

    ["exposure"] = {
      ["ai"] = {
        func = get_light_attr,
        params = { { "material.arnoldLightParams.exposure" }, 0},
      },
      ["dl"] = {
        func = get_light_attr,
        params = { { "material.dlLightParams.exposure" }, 0},
      },
      ["prman"] =  {
        func = get_light_attr,
        params = { { "material.prmanLightParams.exposure" }, 0},
      },
    },

    ["intensity"] = {
      ["ai"] = {
        func = get_light_attr,
        params = { { "material.arnoldLightParams.intensity" }, 1},
      },
      ["dl"] = {
        func = get_light_attr,
        params = { { "material.dlLightParams.intensity" }, 1},
      },
      ["prman"] = {
        func = get_light_attr,
        params = { { "material.arnoldLightParams.intensity" }, 1},
      },
    }

  }

}

function Light:get(attr_name)
  --[[
  Return the light attribute value for the given attribute name

  Returns:
    type depends of what's queried, can be nil
  ]]
  local attr = self.tokens[attr_name] or {}
  attr = attr[RENDERER] or {}  -- return the data for the current render-engine

  local func = attr.func
  local params = attr.params
  if func then
    if params then
      return func(unpack(attr.params))
    else
      return func()
    end
  else
    return nil
  end
end

function Light:to_annotation(annotation)
  --[[
  Args:
    annotation(str): annotation template submitted by the user (with tokens)
  Returns:
    str: annotation with the tokens replaced
  ]]
  for attr_name, _ in pairs(self.tokens) do
    local token = ("<%s>"):format(attr_name)
    local value = stringify(self:get(attr_name))
    annotation = string.gsub(annotation, token, value)
  end

  return annotation

end



local function run()

  local u_annotation_template = get_user_attr("annotation_template", "<name>")
  local u_annotation_colored = get_user_attr("annotation_colored", 1)
  local u_lights_colored = get_user_attr("lights_colored", 1)

  local u_hsl_h = get_user_attr("color_hue", 0)
  local u_hsl_s = get_user_attr("color_saturation", 1)
  local u_hsl_v = get_user_attr("color_value", 1)

  -- 1. Process the annotation
  local annotation = Light:to_annotation(u_annotation_template)
  Interface.SetAttr(
      "viewer.default.annotation.text",
      StringAttribute(annotation)
  )

  -- 2. Process the color
  -- initial color is linear
  local color = Light:get("color") -- table of float or nil
  color = hsv(color, u_hsl_h, u_hsl_s, u_hsl_v)
  -- apply a basic 2.2 transfer-function for display
  color[1] = color[1]^2.2
  color[2] = color[2]^2.2
  color[3] = color[3]^2.2

  if u_annotation_colored == 1 then
    Interface.SetAttr(
        "viewer.default.annotation.color",
        FloatAttribute(color or {0.1, 0.1, 0.1})
    )
  end

  if u_lights_colored == 1 then
    Interface.SetAttr(
        "viewer.default.drawOptions.color",
        FloatAttribute(color or {0.1, 1.0, 1.0})
    )
  end

  --print("[LightViewerAnnotate][run] Finished. Annotation set to <"..annotation..">")

end

-- execute
run()