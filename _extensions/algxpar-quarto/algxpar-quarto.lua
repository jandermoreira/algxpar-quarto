--[[
  Lua filter: replace a pseudocode block with a SVG image created with LaTeX
  Moreira, J. 2023
]]

-- json.lua
-- https://github.com/craigmj/json4lua
local json = require 'json'


local debug = quarto.log.output

-- ---------------------------------------------------
-- Utils

local function starts_with(text, subtext)
  return string.sub(text, 1, 4) == subtext
end


local function copy_table(a_table)
  local new_table = {}
  for key, value in pairs(a_table) do
    if type(value) ~= "table" then
      new_table[key] = value
    else
      new_table[key] = copy_table(value)
    end
  end

  return new_table
end

local function sync_tables(to_table, from_table)
  for key, _ in pairs(to_table) do
    if type(from_table[key]) ~= "table" then
      to_table[key] = from_table[key]
    else
      to_table[key] = copy_table(from_table[key])
    end
  end
end

local function file_exists(filename)
  local file = io.open(filename, "r")
  local exists
  if file == nil then
    exists = false
  else
    exists = true
    file:close()
  end

  return exists
end


local function load_file(filename)
  local file = io.open(filename, "r")
  local contents
  if file ~= nil then
    contents = file:read("a")
    file:close()
  end

  return contents
end


local function is_in(value, table)
  local validate_value = false
  if #table == 0 then
    -- if table is nil, any value is good
    validate_value = true
  else
    validate_value = false
    for _, item in ipairs(table) do
      if value == item and type(value) == type(item) then
        validate_value = true
      end
    end
    if not validate_value then
      debug("algxpar-quarto: Argument", value, "ignored. Must be in ", table)
    end
  end

  return validate_value
end


-- ---------------------------------------------------
-- LaTex to SVG

local latex_code_template = [[
  \documentclass[convert]{standalone}
  \usepackage[T1]{fontenc}
  \usepackage[utf8]{inputenc}
  \usepackage[brazilian]{babel}
  \usepackage{amsmath}
  \usepackage{amssymb}
  \usepackage[brazilian]{algxpar}
  \usepackage{lmodern}
  \usepackage{sourcecodepro}
  \usepackage{xpatch}
  \xapptocmd{\ttfamily}{\frenchspacing}{}{}
  \newcommand{\txtmono}[1]{\scalebox{0.95}{\fontfamily{pcr}\selectfont#1}}
  \newcommand{\txtcaminho}[1]{\scalebox{0.95}{\fontfamily{pcr}\selectfont\bfseries#1}}
  \newcommand{\txtnumero}[2][]{\scalebox{0.95}{\texttt{#2}}\textsubscript{#1}}
  \newcommand{\txtbinario}[1]{\txtnumero[2]{#1}}
  \newcommand{\txthexa}[1]{\txtnumero[16]{#1}}
  \newcommand{\txtbyte}[1]{\txtnumero{#1}}
  \nopagecolor
  \begin{document}
    \sffamily
    \AlgSet{
      language = brazilian,
      comment width = nice,
    }
    \begin{minipage}{15cm}
    %s
    \end{minipage}
  \end{document}
]]

local function create_svg_file(controls, pseudocode_text, filename)
  pandoc.system.make_directory(controls.algxpar_directory, true)

  local pdflatex_log
  pandoc.system.with_temporary_directory(
    "algxpar",
    function(temporary_directory)
      pandoc.system.with_working_directory(
        temporary_directory,
        function()
          svg_filename = controls.base_path ..
              controls.algxpar_directory .. "/" .. filename
          if not file_exists(svg_filename) then
            local tex_file = io.open("pseudocode.tex", "w")
            if tex_file ~= nil then
              tex_file:write(latex_code_template:format(pseudocode_text))
              tex_file:close()
            end
            if os.execute("pdflatex -interaction=nonstopmode " ..
                  "pseudocode.tex > /dev/null") then
              os.execute("pdf2svg pseudocode.pdf " .. svg_filename)
              os.execute("rm -f /tmp/tail.log")
            else
              os.execute("cp pseudocode.log /tmp/" .. filename .. ".log")
              os.execute("cp pseudocode.tex /tmp/" .. filename .. ".tex")
              os.execute("tail -n 50 /tmp/" .. filename .. ".log > tail.log")
              pdflatex_log = pseudocode_text .. "\n\n(...)\n" .. load_file("tail.log")
              debug("algxpar-quarto: pdflatex run failed. See /tmp/" ..
                filename .. ".log")
            end
          end
          return nil
        end
      )
      return nil
    end
  )

  return pdflatex_log
end


-- ---------------------------------------------------
-- Block rendering

local function format_algorithm_caption(controls, caption_text)
  local caption
  if quarto.doc.is_format("pdf") then
    if not caption_text then
      caption = pandoc.List({})
    else
      caption = pandoc.read(caption_text, "markdown").blocks[1].content
    end
  else
    if not caption_text then
      caption = pandoc.List({})
      -- caption = pandoc.Para(
      --   pandoc.Str(controls.algorithm_title .. " " ..
      --     controls.chapter_number .. controls.algorithm_counter)
      -- )
    else
      caption = pandoc.read(controls.algorithm_title .. " " ..
        controls.chapter_number .. controls.algorithm_counter .. ": " .. caption_text, "markdown").blocks[1]
    end
  end
  return caption
end


local function render_latex(controls, block)
  local element
  if controls["label"] then
    label = string.sub(controls["label"], 2)
  else
    label = ""
  end
  if not controls["label"] then
    element = { pandoc.RawInline("latex", "\n\\medskip" .. block.text) }
  else
    local caption_content = format_algorithm_caption(controls, controls["title"])
    local caption
    if not controls["pdf_float"] then
      caption = pandoc.Plain(pandoc.RawInline("latex",
        "\\begin{algorithm}[H]\n\\caption{\\label{" .. label .. "}"))
    else
      caption = pandoc.Plain(pandoc.RawInline("latex",
        "\\begin{algorithm}\n\\caption{\\label{" .. label .. "}"))
    end
    for _, element in ipairs(caption_content) do
      caption.content:insert(element)
    end
    caption.content:insert(pandoc.RawInline("latex", "}\n\\begingroup%\n"))
    element = {
      caption,
      pandoc.RawInline("latex", block.text),
      pandoc.RawInline("latex", "\\endgroup\n\\end{algorithm}"),
    }
  end
  return element
end


local function render_html(controls, block)
  local unique_name = "pseudocode." .. pandoc.sha1(block.text) .. ".svg"
  local label
  if controls["label"] then
    label = string.sub(controls["label"], 2)
  else
    label = ""
  end
  local caption = format_algorithm_caption(controls, controls["title"])
  local pdflatex_log = create_svg_file(controls, block.text, unique_name)
  if pdflatex_log then
    element = pandoc.CodeBlock(pdflatex_log)
  else
    element = pandoc.Div(
      {
        pandoc.RawInline("html", '<figcaption class="figure-caption">'),
        caption,
        pandoc.RawInline("html", "</figcaption>"),
        pandoc.Para({
          pandoc.Image(
            {},
            controls.html_link_prefix .. controls.algxpar_directory .. "/" .. unique_name,
            "",
            ---@diagnostic disable-next-line: missing-fields
            { width = "648px", alt = pandoc.utils.stringify(caption) })
        })
      },
      ---@diagnostic disable-next-line: missing-fields
      { id = label }
    )
  end
  controls.list_of_references[label] = {
    label = controls.algorithm_prefix .. " " .. controls.chapter_number ..
        controls.algorithm_counter,
    caption = "",
    file = controls.html_filename,
    target = '#' .. label,
    title = "",
  }

  return element
end


-- ---------------------------------------------------
-- CodeBlock filters

local function canonize_key(key)
  return string.gsub(key, "[ -]", "_")
end

local function canonize_data(data)
  local value
  if data == "true" then
    value = true
  elseif data == "false" then
    value = false
  elseif string.sub(data, 1, 1) == '"' and
      string.sub(data, -1, -1) == '"' then
    value = string.sub(data, 2, -2)
  else
    value = data
  end

  return value
end

local function get_local_controls(controls, attributes, source_code)
  local local_controls = copy_table(controls)

  -- from attributes
  for option, value in pairs(attributes) do
    local_controls[canonize_key(option)] = canonize_data(value)
  end

  -- from block text (override those from attributes)
  local continue_search = true
  for line in string.gmatch(source_code, "([^\n]*)\n") do
    if string.match(line, "^%s*$") or not string.match(line, "%s*%%|%s.*") then
      continue_search = false
    end
    if continue_search then
      option, value = string.match(line, "%s*%%|%s*([^:]*):%s%s*(.*[^%s$])")
      local_controls[canonize_key(option)] = canonize_data(value)
    end
  end

  return local_controls
end

local function pseudocode_block_filter(controls)
  local function run_pseudocode_block_filter(block)
    local element
    if not block.attr.classes:includes("pseudocode") then
      element = block
    else
      local local_controls = get_local_controls(controls,
        block.attr.attributes, block.text)
      debug(local_controls["label"])
      if local_controls.label then
        controls.algorithm_counter = controls.algorithm_counter + 1
        local_controls.algorithm_counter = controls.algorithm_counter
      end
      if quarto.doc.is_format("pdf") then
        element = render_latex(local_controls, block)
      else -- html and epub
        element = render_html(local_controls, block)
      end
      sync_tables(controls, local_controls)
    end
    return element
  end

  return { CodeBlock = run_pseudocode_block_filter }
end


-- ---------------------------------------------------
-- Cite filters

local function cite_latex(controls, label)
  return pandoc.RawInline("latex",
    controls.algorithm_prefix .. "~" .. controls.chapter_number ..
    "\\ref{" .. label .. "}")
end


local function cite_html(controls, citation)
  local element
  if controls.list_of_references[citation.id] then
    local target = controls.html_link_prefix ..
        controls.list_of_references[citation.id].file ..
        controls.list_of_references[citation.id].target
    local link = pandoc.Link(
      controls.list_of_references[citation.id].label,
      target,
      controls.list_of_references[citation.id].title
    )
    element = link
  else
    element = pandoc.Str("??" .. citation.id)
    debug("algxpar-quarto: Unknown reference '@" .. citation.id .. "'.")
    debug("algxpar-quarto: You can try to do a second pass render to correct it.")
  end
  return element
end


local function cite_plain(controls, citation)
  local element
  if controls.list_of_references[citation.id] then
    element = pandoc.Str(controls.algorithm_prefix .. " " ..
      controls.list_of_references[citation.id].label)
  else
    element = pandoc.Str("??" .. citation.id)
    debug("algxpar-quarto: Unknown reference '@" .. citation.id .. "'.")
    debug("algxpar-quarto: You can try to do a second pass render to correct it.")
  end
  return element
end


-- ---------------------------------------------------
-- Crossrefs filtering

local function process_crossrefs_filter(controls)
  local function run_process_crossrefs_filter(citation)
    local element = citation
    for _, single_citation in pairs(citation.citations) do
      if starts_with(single_citation.id, "alg-") then
        if quarto.doc.is_format("pdf") then
          element = cite_latex(controls, single_citation.id)
        elseif quarto.doc.is_format("html") then
          element = cite_html(controls, single_citation)
        else
          element = cite_plain(controls, single_citation)
        end
      end
    end
    return element
  end

  return { Cite = run_process_crossrefs_filter }
end


local function initialize_list_of_references(controls)
  local list
  if controls.mode ~= "project" then
    list = {}
  else
    algxpar_path = controls.base_path .. controls.algxpar_directory
    pandoc.system.make_directory(algxpar_path, true)
    pandoc.system.with_working_directory(
      algxpar_path,
      function()
        local filename = "references.json"
        local file = io.open(filename, "r")
        if not file then
          list = {}
        else
          list = json.decode(file:read("a"))
          file:close()
        end
        return nil
      end
    )
  end
  return list
end


-- ---------------------------------------------------
-- algxpar


local function create_default_controls(meta_algxpar)
  local function get_meta_boolean(option, default_value)
    local value
    if type(meta_algxpar[option]) == "boolean" then
      value = meta_algxpar[option]
    else
      if meta_algxpar[option] then -- not nil
        debug("algxpar-quarto:", option, "must be either true or false.")
        debug("algxpar-quarto:", option, "set to ", default_value)
      end
      value = default_value
    end

    return value
  end

  local function get_meta_string(option, default_value, valid_values)
    local value
    if meta_algxpar[option] then
      value = pandoc.utils.stringify(meta_algxpar[option])
      -- todo: check valid_values
    else
      value = default_value
    end

    return value
  end

  meta_algxpar = meta_algxpar or {} -- avoid nil
  local default_controls = {
    mode = "file",
    base_path = "",
    algxpar_directory = "algxpar",
    list_of_references = {},
    chapter_number = "",
    algorithm_counter = 0,
    html_filename = "",
    html_link_prefix = "",
    algorithm_title = get_meta_string("algorithm-title", "Algorithm"),
    algorithm_prefix = get_meta_string("algorithm-prefix", "Algorithm"),
    pdf_float = get_meta_boolean("pdf-float", true),
  }

  return default_controls
end


local function initialize_algxpar(meta)
  -- Global controls
  local controls = create_default_controls(meta["algxpar"])

  local quarto_filename = quarto.doc.input_file

  local is_project = os.getenv("QUARTO_PROJECT_DIR")
  if is_project then
    controls.mode = "project"
    controls.base_path = os.getenv("QUARTO_PROJECT_DIR")
    quarto_filename = string.sub(quarto_filename, #controls.base_path + 2)
    controls.html_filename = quarto_filename:gsub("%.qmd$", ".html")
    if quarto.doc.is_format("html") then
      local _, directoryLevel = quarto_filename:gsub("/", "")
      for _ = 1, directoryLevel do
        controls.html_link_prefix = "../" .. controls.html_link_prefix
      end
    end
    controls.base_path = controls.base_path .. "/"
  else
    controls.base_path = string.match(quarto_filename, ".*/")
  end


  --  Get chapter number if it's a book
  if meta["book"] then
    for _, render in pairs(meta["book"]["render"]) do
      if render["file"] and render["number"] and
          pandoc.utils.stringify(render["file"]) == quarto_filename then
        controls.chapter_number =
            pandoc.utils.stringify(render["number"]) .. "."
      end
    end
  end

  if quarto.doc.is_format("pdf") then
    quarto.doc.use_latex_package("float")
    quarto.doc.use_latex_package("algorithm")
    quarto.doc.use_latex_package("algxpar", "brazilian")
    quarto.doc.include_text("before-body",
      "\\floatstyle{plaintop}\\restylefloat{algorithm}\n" ..
      "\\floatname{algorithm}{" .. controls.algorithm_title .. "}"
    )
    if is_project then
      quarto.doc.include_text("before-body",
        "\\counterwithin{algorithm}{chapter}")
    end
  end

  controls.list_of_references = initialize_list_of_references(controls)

  return controls
end


local function terminate_algxpar(controls)
  if controls.mode == "project" then
    pandoc.system.with_working_directory(
      controls.base_path .. controls.algxpar_directory,
      function()
        local referenceFile = "references.json"
        file = io.open(referenceFile, "w")
        if file then
          encoded_json = json.encode(controls.list_of_references)
          file:write(encoded_json)
          file:close()
        end
        return nil
      end
    )
  end
end

-- ---------------------------------------------------
-- Info

local function debug_print_info(controls)
  debug("")
  debug("algxpar-quarto:")
  -- debug("  current file: " .. quarto_filename)
  if controls.mode == "project" then
    debug("  mode: project")
    debug("  project directory: " .. controls.base_path)
    debug("  chapter prefix: " .. controls.chapter_number)
  else
    debug("  mode: file")
  end
  debug("  algxpar directory: " .. controls.algxpar_directory)
  if quarto.doc.is_format("html") then
    debug("  links to: " .. controls.html_filename)
    debug("  root is in: " .. controls.html_link_prefix)
  end
  debug("")
end


local function algxpar(doc)
  local controls = initialize_algxpar(doc.meta)

  -- Render pseudocode and grab labels for references
  doc = doc:walk(pseudocode_block_filter(controls))

  -- Process cross references
  doc = doc:walk(process_crossrefs_filter(controls))


  -- Update list of references to file
  terminate_algxpar(controls)

  -- debug_print_info(global_controls)

  return doc
end


-- ---------------------------------------------------
-- The filter!

return {
  { Pandoc = algxpar },
}
