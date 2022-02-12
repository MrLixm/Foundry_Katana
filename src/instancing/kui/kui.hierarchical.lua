--[[
todo
version=0.0.2
]]


local logging = require "lllogger"
local logger = logging:new("kui.hierarchical")
logger:set_level("debug")
logger.formatting:set_tbl_display_functions(false)

--[[ __________________________________________________________________________
  LUA UTILITIES
]]
-- we make some global functions local as this will improve performances in
-- heavy loops
local tostring = tostring
local stringformat = string.format
local select = select
local tableconcat = table.concat

local function conkat(...)
  --[[
  The loop-safe string concatenation method.
  ]]
  local buf = {}
  for i=1, select("#",...) do
    buf[ #buf + 1 ] = tostring(select(i,...))
  end
  return tableconcat(buf)
end

local function logerror(...)
  --[[
  log an error first then stop the script by raising a lua error()

  Args:
    ...(any): message to log, composed of multiple arguments that will be
      converted to string using tostring()
  ]]
  local logmsg = conkat(...)
  logger:error(logmsg)
  error(logmsg)

end


--[[ __________________________________________________________________________
  Katana UTILITIES
]]

local function get_attribute_class(kattribute)
  --[[
  Returned a non-instanced version of the class type used by the given arg.

  Args:
    kattribute(IntAttribute or FloatAttribute or DoubleAttribute or StringAttribute)
  Returns:
    table: DataAttribute
  ]]
  if Attribute.IsInt(kattribute) == true then
    return IntAttribute
  elseif Attribute.IsFloat(kattribute) == true then
    return FloatAttribute
  elseif Attribute.IsDouble(kattribute) == true then
    return DoubleAttribute
  elseif Attribute.IsString(kattribute) == true then
    return StringAttribute
  else
    logerror(
      "[get_attribute_class] passed attribute <",
      kattribute,
      ">is not supported."
    )
  end
end

local function get_user_attr(time, name, default_value)
    --[[
    Return an OpScipt user attribute.
    If not found return the default_value. (unless asked to raise an error)

    Args:
        time(int): frame the attribute must be queried at
        name(str): attribute location (don't need the <user.>)
        default_value(any): value to return if user attr not found
          you can use the special token <$error> to raise an error instead
    Returns:
        table: Katana DataAttribute or default value wrap in a table
    ]]
    local argvalue = Interface.GetOpArg(conkat("user.",name))

    if argvalue then
      return argvalue:getNearestSample(time)

    elseif default_value=="$error" then
      logerror("[get_user_attr] user attribute <",name,"> not found.")

    else
      return { default_value }

    end

end

local function get_loc_attr(location, attr_path, time, default)
  --[[
  Get the given attribute on the location at given time.
  Raise an error is nil result I found or return <default> if specified.

  If default is not nil and the attribute is not found, it is instead returned.

  Args:
    location(str): scene graph location to extract teh attribute from
    attr_path(str): path of the attribute on the location
    time(int): frame to extract the value from
    default(any or nil): value to return if attribute not found.
  Returns:
    table: table of 2: {value table, table representing the original data type}
  ]]

  local lattr = Interface.GetAttr(attr_path, location)

  if not lattr then

    if default ~= nil then
      return default
    end

    logerror(
      "[get_loc_attr] Attr <",attr_path,"> not found on source <",location,">."
    )

  end

  lattr = lattr:getNearestSample(time)

  if not lattr then

    if default ~= nil then
      return default
    end

    logerror(
      "[get_loc_attr] Attr <", attr_path, "> is nil on source <", location,
      "> at time=", time
    )

  end

  return lattr, get_attribute_class(lattr)

end

--[[ __________________________________________________________________________
  API
]]


local InstancingMethod = {}

function InstancingMethod:new(point_data)
  --[[
  Base class to implement support for an instancing method.
  Made the link between pointcloudData and instance creation.

  Args:
    point_data(pointcloudData) : pointcloudData instance that has been built.

  Attributes:
    pdata(pointcloudData): pointcloudData instance
    name_tmp(str): name to give to the instances, with tokens.
  ]]

  local attrs = {
    pdata = point_data,
    name_tmp = false,
  }

  function attrs:build()
    logerror("[InstancingMethod][build] NotImplementedError")
  end

  function attrs:set_name_template(name)
    self["name_tmp"] = name
  end


  return attrs

end


-- Used for InstancingHierarchical
-- key is the token to query and value is the target attribute path
-- if the token doesnt have any value on point_data it will not be added.
local token_target = {
  ["scale"]="xform.group0.scale",
  ["translation"]="xform.group0.translate",
  ["matrix"]="xform.group0.matrix",
  -- if the pdata was validated, we for sure have rotationX/Y/Z
  ["rotationX"]="xform.group0.rotateX",
  ["rotationY"]="xform.group0.rotateY",
  ["rotationZ"]="xform.group0.rotateZ"
}


local function InstancingHierarchical(point_data)
  --[[
  Args:
    point_data(pointcloudData) : pointcloudData instance that has been built.
  ]]
  local inner = InstancingMethod:new(point_data)

  -- override build()
  function inner:build()

    local instance
    -- /!\ perfs
    for pid=0, self.pdata.point_count - 1 do
      instance = InstanceHierarchical:new(self.name_tmp, pid)
      instance:build_from_pdata(point_data)
      instance:finalize()
    end

  end

  return inner
end

local function InstancingArray(point_data)
    --[[
  Args:
    point_data(pointcloudData) : pointcloudData instance that has been built.
  ]]
  logerror("Method array not supported yet !") -- TODO
  local inner = InstancingMethod:new(point_data)
  return inner
end


local InstanceHierarchical = {}

function InstanceHierarchical:new(name, id)
  --[[
  A single hierarchical instance location represented as a class.

  /!\ All operations has to be as light-weight as possible as this can be
  instanced thousands of times.

  Args:
    name(str): name template to give to the instance (with tokens)
    id(int): unique identifier for the instance, usually the loop current index

  Attributes:
    data(table):
      store attributes progressively set on the instance to
      be reused at build time for the instance name.
    gb(GroupBuilder):
    id(int):
      unique identifier for the instance, usually the loop current index
    nametmp(str):
      name template to give to the instance (so with tokens)
  ]]

  local attrs = {
    nametmp = name,
    id = id,
    gb = GroupBuilder(),
    data = {
      ["instance_source"] = false,
      ["source_index"] = false
    }
  }

  attrs.gb:update(Interface.GetOpArg())
  attrs.gb:set("childAttrs.type", StringAttribute("instance"))

  function attrs:add(attr_path, attr_value)
    --[[
    Args:
      attr_path(str): where the attribute should live on the instance.
        Path relative to the instance.
      attr_value(DataAttribute): Katana DataAttribute instance with the data
    ]]
    self.gb:set(
        conkat("childAttrs.", attr_path),
        attr_value
    )
  end

  function attrs:build_from_pdata(point_data)
    --[[
    Convenient method to build the instance from a pointCloudData instance
    at the current point index (id attribute).
    ]]

    -- 1. PROCESS COMMON ATTRIBUTES
    local value
    for token, target in pairs(token_target) do
      -- get value at current point index
      value = point_data:get_attr_value(token, self.id)
      -- if value add it to this instance
      if value ~= nil then
        self:add(target, value)
      end
    end
    -- 2. PROCESS ARBITRARY ATTRIBUTES
    for target, data in pairs(point_data["arbitrary"]) do
        -- TODO wip
    end


    -- end function
  end

  function attrs:set_instance_source(instance_source, index)
    --[[
  Args:
  instance_source(str): existing scene graph location
  index(str or int): index on source from which this instance has been
  computed.
  ]]
    self.data.instance_source = instance_source
    self.data.source_index = index
    self.add(
      "geometry.instanceSource",
      StringAttribute(instance_source)
    )
  end

  function attrs:set_proxy(proxy_path)
    -- TODO, might not be implemented
  end

  function attrs:get_name()
    --[[
    Compute the instance location name from the given template (self.nametmp)
     based on its attributes.

    TODO some perfs might be gained here, see later.

    Returns:
      str: final instance name
    ]]
    local out = self.nametmp

    -- safety check that $id is present
    if not out:match("%$id") then
      logerror(
          "[InstanceHierarchical][get_name] Passed name template <",
          out,
          "> doesn't have the mandatory <$id> token."
      )
    end

    -- extract the number of digit that must be used for the id
    local digits = out:match("%$id(%d*)")
    if not digits then
      digits = 0
    end

    -- create the token values
    local sourcename local sourceindex

    if self.data.instance_source then
      sourcename = tostring(self.data.instance_source:gsub(".+/", ""))
    else
      sourcename = ""
    end

    if self.data.source_index then
      sourceindex = tostring(self.data.source_index)
    else
      sourceindex = ""
    end

    -- Assign the tokens to their value
    -- key is a regex, value must be a string
    local tokens  = {
      ["%$id%d*"] = stringformat(conkat("%0", digits, "d"), self.id),
      ["%$sourcename"] = sourcename,
      ["%$sourceindex"] = sourceindex
    }

    -- replace token on name template
    for token, value in pairs(tokens) do
      out = tostring(out:gsub(token, value))
    end

    return out

  end

  function attrs:finalize()
    --[[
    Last method to call once you finish building the Instance.
    ]]
    Interface.CreateChild(
      self:get_name(),
      Interface.GetOpType(),
      self.gb:build()
    )
  end

  return attrs

end

local pointcloudData = {}
function pointcloudData:new(location, time)
  --[[
  Represents attribute data holded on a pointcloud location. (or actually
  any locations with the supported <instancing> attributes).

  Notes:
    Once validated, <rotation> attribute is splitted to its
     <rotationX/Y/Z> brothers (if only <rotation> was specified first)

  Args:
    location(str): scene graph location of the pointcloud
    time(int): time at which attributes must be queried

  Attributes:
    time(int): time at which attributes must be queried
    location(str): scene graph location of the pointcloud
    common(table): keys are supported token value (+$)
    sources(table): num keys
    arbitrary(table): keys are instance target attribute path

  [sources]
  {
    0: {
      "path"(str):
        scene graph location of the instance source
      "index"(num):
        index it's correspond to on the pointCloud (offset has been applied)
      "proxy"(Optional[str]):
        proxy geometry location
    }
    1: ...
  }
  [arbitrary]
  {
    "target attribute path": {
      "path"(str):
        attribute path relative to the source.
      "grouping"(num):
         how much value belongs to an individual point.
      "multiplier"(num):
        quick way to multiply values.
      "values"(table):
        table of value gathered on the source using the above path
      "type"(DataAttribute):
        DataAttribute class not instanced that correspond to values
    }
    ...
  }
  [common]
  {
    "token (without the $)": {
      "path"(str):
        attribute path relative to the source.
      "grouping"(num):
         how much value belongs to an individual point.
      "multiplier"(num):
        quick way to multiply values.
      "values"(table):
        table of value gathered on the source using the above path
      "type"(DataAttribute):
        DataAttribute class not instanced that correspond to values
    }
    ...
  }
  ]]

  local attrs = {
    ["time"]=time,
    ["location"]=location,
    ["common"]={
      ["scale"]=false,
      ["rotation"]=false,
      ["translation"]=false,
      ["index"]=false,
      ["points"]=false,
      ["matrix"]=false,
      ["rotationX"]=false,
      ["rotationY"]=false,
      ["rotationZ"]=false
    },
    ["sources"]=false,
    ["arbitrary"]=false,
    ["point_count"]=false
  }

  function attrs:check_token(token)
    --[[
    Check if the given token is a valid token and if so return it without the $

    Args:
      token(str): string that should start with <$>
      source(str): scene graph location where this token is stored
    Returns:
      str: token without the <$>
    ]]
    for token_supported, _ in pairs(self.common) do
      -- add the <$> in font of the known token for comparison with the arg
      token_supported = conkat("$", token_supported)
      -- if similar retur the arg token without the <$>
      if token_supported == token then
        return token:gsub("%$", "")
      end
    end

    logerror(
      "[check_token] invalid token <",token,"> on source <",self.location,">."
    )

  end

  function attrs:get_attr_value(attr_name, pid)
    --[[
    Return the value for the given attribute.
    The value has been multiplied as specified by the attribute of the same
    name

    Args:
      attr_name(str):
        name for the key to query, no matter if it's a common or an arbitrary
        attribute name.
      pid(int or nil): point index: which point to use. If not specified return
        the whole table.

    Returns:
      object or nil:
        type depends of args. Nil if the attr_name was never processed (empty).
    ]]

    local attrdata = self["common"][attr_name]
    if attrdata == nil then
      attrdata = self["arbitrary"][attr_name]
      if attrdata == nil then
        logerror(
          "[pointcloudData][get_value4index]",
          "Can't find attribute <",
          attr_name,
          "> on instance for location <",
          self.location,
          ">."
        )
      end
    end

    if attrdata == false then
      return nil
    end

    local value local valuetype

    if pid == nil then
      value = attrdata["values"]  -- table
    else
      value = attrdata["values"][pid]  -- single value
    end
    -- TODO add multiplier and DataAttribute
    return value

  end

  function attrs:at_pindex(pindex)
    -- todo
    return {}
  end

  function attrs:convert_rotation2rotationaxis()
    --[[
    Execute after self:validate
    ! heavy ! Process through all the rotation points
    ]]

    -- check of course if the attribute is built before starting anything
    if not self.common.rotation then
      return
    end

    local rx = {}
    local ry = {}
    local rz = {}

    local rall_data = {
      { rx, {1.0, 0.0, 0.0} }, -- x
      { ry, {0.0, 1.0, 0.0} }, -- y
      { rz, {0.0, 0.0, 1.0} }  -- z
    }
    local rvalues local raxis

    -- TODO check how grouping can affect that
    -- iterate trough all rotation values with are assumed to be in x,y,z order
    -- /!\ Perfs
    for i=0, #self.common.rotation.values / self.common.rotation.grouping - 1 do

      -- iterate trough each axis x,y,z
      for rindex, rdata in ipairs(rall_data) do
        -- rindex=[1,2,3] ; rdata=[{ {}, {1.0, 0.0, 0.0} }, ...]
        rvalues, raxis = rdata[1], rdata[2]

        rvalues[#rvalues + 1] = self.common.rotation.values[i*self.common.rotation.grouping + rindex]
        rvalues[#rvalues + 1] = raxis[1]
        rvalues[#rvalues + 1] = raxis[2]
        rvalues[#rvalues + 1] = raxis[3]
      end

    end

    for i, token in ipairs({"rotationX", "rotationY", "rotationZ"}) do
      self["common"][token] = {
        ["path"] = "$rotation",
        ["grouping"] = 4,
        ["multiplier"] = self.common.rotation.multiplier,
        ["values"] = rall_data[i][1],
        ["type"] = self.common.rotation.type
      }
    end

  end

  function attrs:build()
    -- query data on source to build the table
    self:build_common()
    self:build_arbitrary()
    self:build_sources()
    -- check that the data queried above is valid
    self:validate()
    -- then modify this data for final use
    self:convert_rotation2rotationaxis()
  end

  function attrs:build_sources()
    --[[
    Build the <sources> key from the <instancing.data.sources> attribute
     on source location.

    This source attribute is a X*3 string array as:
      [0] instance source location,
      [1] instance source index,
      [2] proxy geometry location

    ]]

      -- get the attribute on the pc
    local data_sources = get_loc_attr(
        self.location,
        "instancing.data.sources",
        self.time
    )

    local data_index_offset = get_loc_attr(
        self.location,
        "instancing.settings.index_offset",
        self.time,
        0 -- default value if attr not existing
    )

    local path
    local iindex
    local proxy
    self["sources"] = {}

    -- start building the sources key ------------------------------------------
    for i=0, #data_sources / 3 - 1 do

      path = data_sources[3*i+1]
      iindex = tonumber(data_sources[3*i+2]) - data_index_offset
      proxy = data_sources[3*i+3]

      -- process special cases here --------------------
      -- none yet

      self["sources"][#self["sources"] + 1] = {
        ["path"] = path,
        ["index"] = iindex,
        ["proxy"] = proxy
      }

    end

  end

  function attrs:build_arbitrary()
    --[[
    Build the <arbitrary> key from the <instancing.data.arbitrary>
      attribute on source location
    ]]

      -- get the attribute on the pc
    local data_arbtr = get_loc_attr(
        self.location,
        "instancing.data.arbitrary",
        self.time
    )
    local target
    local grouping
    local multiplier
    local path
    local pcvalues
    local value_type
    self["arbitrary"] = {}

    -- start building the common key ------------------------------------------
    for i=0, #data_arbtr / 4 - 1 do

      path = data_arbtr[4*i+1]
      target = data_arbtr[4*i+2]
      grouping = tonumber(data_arbtr[4*i+3])
      multiplier = tonumber(data_arbtr[4*i+4])
      pcvalues, value_type = get_loc_attr(self.location, path, self.time)

      -- process special cases here --------------------
      -- none yet

      self["arbitrary"][target] = {
        ["path"] = path,
        ["grouping"] = grouping,
        ["multiplier"] = multiplier,
        ["values"] = pcvalues,
        ["type"] = value_type
      }

    end

  end

  function attrs:build_common()
    --[[
    Build the <common> key from the <instancing.data.common>
      attribute on source location.
    The attribute is a X*4 string array as :
      [0] attribute path relative to the source.
      [1] token to specify what kind of data [0] corresponds to.
      [2] value grouping : how much value belongs to an individual point.
      [3] value multiplier : quick way to multiply values.

    The $points token require a special processing.
    ]]

      -- get the attribute on the pc
    local data_common = get_loc_attr(
        self.location,
        "instancing.data.common",
        self.time
    )

    local token
    local grouping
    local multiplier
    local path
    local pcvalues
    local value_type
    local pointsvalue = {}

    -- start building the common key ------------------------------------------
    for i=0, #data_common / 4 - 1 do

      path = data_common[4*i+1]
      token = self:check_token(data_common[4*i+2]) -- return without the "$" !
      grouping = tonumber(data_common[4*i+3])
      multiplier = tonumber(data_common[4*i+4])
      pcvalues, value_type = get_loc_attr(self.location, path, self.time)

      -- process special cases here --------------------
      if token == "points" then
        -- <values> key should always be a table so just fill it with 0 here
        for pointindex=1, #pcvalues / grouping * multiplier do
          pointsvalue[pointindex] = 0
        end
        pcvalues = pointsvalue
        grouping = 1
      end

      self["common"][token] = {
        ["path"] = path,
        ["grouping"] = grouping,
        ["multiplier"] = multiplier,
        ["values"] = pcvalues,
        ["type"] = value_type
      }

    end

    -- end build_common
  end

  function attrs:validate()
    --[[
    To call after built operations.
    Verify that self table is properly built.
    Also clean the attributes and set "point_count" one.
    TODO see if arbitrary is also needed to be validated
    ]]

    -- attr points must always exists
    if not self.common.points then
      logerror(
          "[pointcloudData][validate] Missing token $points on source <",
          self.location,
          ">."
      )
    end

    -- we need at least one instance source
    if not self.sources then
      logerror(
          "[pointcloudData][validate] No instance sources specified \z
           for source <",
          self.location,
          ">."
      )
    end

    -- every instance source need the index to be declared
    for _, isource_data in ipairs(self.sources) do
      if not isource_data["index"] then
        logerror(
            "[pointcloudData][validate] No index specified for \z
            instance source <",
            self.isource_data["path"],
            "> for source location <",
            self.location,
            ">."
        )
      end
    end

    -- there is no point to have the matrix token + one of the trs so warn
    -- and reset the trs attributes
    if self.common.matrix and (
        self.common.translation or
        self.common.rotation or
        self.common.scale or
        self.common.rotationX
    ) then
      logger:warning(
          "[pointcloudData][validate] Source <", self.location,
          "> declare a $matrix token but also one of the trs. In that case \z
           $matrix take the priority."
      )
      self.common.translation = false
      self.common.rotation = false
      self.common.scale = false
      self.common.rotationX = false
      self.common.rotationY = false
      self.common.rotationZ = false
    end

    -- verify that if one rotationX/Y/Z is declared, all other 2 also are
    if not (
        self.common.rotationX and
        self.common.rotationY and
        self.common.rotationZ
    ) then
      if (
          self.common.rotationX or
          self.common.rotationY or
          self.common.rotationZ
      ) then
        logerror(
          "[pointcloudData][validate] Source <", self.location,
          "> doesn't have all the <rotationX/Y/Z> tokens declared \z
          (but declare currently at least one)."
        )
      end
    end

    -- verify that if $rotation is declared no rotationX/Y/Z is also declared
    if self.common.rotation and (
        self.common.rotationX or
        self.common.rotationY or
        self.common.rotationZ
    ) then
      logger:warning(
          "[pointcloudData][validate] Source <", self.location,
          "> declare a rotation token but also one of the $rotationX/Y/Z.\z
           In that case $rotation take the priority."
      )
    end

    local pointsn = #self.common.points.values * self.common.points.multiplier
    local attrlength
    for attrname, attrdata in ipairs(self.common) do
      -- attrdata can be <false> if not built so skip if so, I wish lua has a
      -- "continue" keyword like in python !
      if attrdata then
        --we check first that the <grouping> and <points> attribute seems valid
        attrlength = #(attrdata.values) / attrdata.grouping
        if attrlength ~= pointsn then
          logerror(
          "[pointcloudData][validate] Common attribute <", attrname,
          "> as an odd number of values : ", tostring(#(attrdata.values)),
          " / ", tostring(attrdata.grouping), " = ", attrlength,
          " while $points=", pointsn
          )
        end
        -- end if attrdata is not false/nil
      end
      -- end for attrname, attrdata
    end

    self["point_count"] = pointsn
    -- end for validate()
  end

  return attrs

end

local function create_instances()
  --[[
  When Interface at root
  ]]
  local stime = os.clock()
  local time = Interface.GetCurrentTime() -- int

  local u_pointcloud_sg = get_user_attr( time, "pointcloud_sg", "$error" )[1]
  local u_instance_name = get_user_attr( time, "instance_name", "$error" )[1]
  local u_instance_method = get_user_attr( time, "instance_method", "$error" )[1]

  -- process the source pointcloud
  logger:info("Started processing source <", u_pointcloud_sg, ">.")
  local pointdata
  pointdata = pointcloudData:new(u_pointcloud_sg, time)
  pointdata:build()
  logger:debug("pointdata = \n", pointdata, "\n")

  -- start instancing
  local instance

  if u_instance_method == "hierarchical" then

    instance = InstancingHierarchical:new(pointdata)
    instance:set_name_template(u_instance_name)
    instance:build()

  elseif u_instance_method == "array" then

    instance = InstancingArray:new(pointdata)
    instance:set_name_template(u_instance_name)
    instance:build()

  end

  stime = os.clock() - stime
  logger:info(
      conkat("Finished in ",stime,"s for pointcloud <",u_pointcloud_sg,">.")
  )

end

local function finalize_instances()
  --[[
  When Interface is not at root.
  Only usefull for hierarchical but still called for array.

  Not recommended to log anything here as the message will be repeated times
  the number of instances (so can be thousands !)
  ]]

  local childAttrs = Interface.GetOpArg("childAttrs")

  for i=0, childAttrs:getNumberOfChildren() - 1 do

    Interface.SetAttr(
        childAttrs:getChildName(i),
        childAttrs:getChildByIndex(i)
    )

  end

  logger:debug("Finished for <", childAttrs, ">.")  -- TODO remove this when code finished

end

local function run()
  --[[
  First function executed.
  ]]

  if Interface.AtRoot() then
    print(string.rep("\n", 10))
    create_instances()
  else
    finalize_instances()
  end

end

-- execute
run()