--[[
  Lua filter: replace a pseudocode block with a SVG image created with LaTeX
  Moreira, J. 2023
]]

-- json.lua
-- https://github.com/craigmj/json4lua
local json = require 'json'


local debug = quarto.log.output


local function starts_with(text, subtext)
  return string.sub(text, 1, 4) == subtext
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
    \AlgSet{language = brazilian}
    \begin{minipage}{15cm}
    %s
    \end{minipage}
  \end{document}
]]

local function create_svg_file(controls, pseudocode_text, filename)
  pandoc.system.make_directory(controls.algxpar_directory, true)
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
            else
              os.execute("cp pseudocode.log /tmp/" .. filename .. ".log")
              os.execute("cp pseudocode.tex /tmp/" .. filename .. ".tex")
              debug("*** pdflatex failed. See /tmp/" ..
                filename .. ".log")
            end
          end
          return nil
        end
      )
      return nil
    end
  )
end


local function algorithm_caption(controls, caption_text)
  local caption
  if quarto.doc.is_format("pdf") then
    if not caption_text then
      caption = pandoc.List({})
    else
      return pandoc.read(caption_text, "markdown").blocks[1].content
    end
  else
    if not caption_text then
      caption = pandoc.Para(
        pandoc.Str(controls.algorithm_title .. " " ..
          controls.chapter_number .. controls.algorithm_counter)
      )
    else
      caption = pandoc.read(controls.algorithm_title .. " " ..
        controls.chapter_number .. controls.algorithm_counter .. ": " .. caption_text, "markdown").blocks[1]
    end
  end
  return caption
end


local function render_latex(controls, block)
  label = string.sub(block.attr.attributes["label"], 2)
  local caption_content = algorithm_caption(controls, block.attr.attributes["title"])
  local caption = pandoc.Plain(pandoc.RawInline("latex",
    "\\begin{algorithm}\n\\caption{\\label{" .. label .. "}"))
  for _, element in ipairs(caption_content) do
    caption.content:insert(element)
  end
  caption.content:insert(pandoc.RawInline("latex", "}\n\\begingroup%\n"))
  return {
    caption,
    pandoc.RawInline("latex", block.text),
    pandoc.RawInline("latex", "\\endgroup\n\\end{algorithm}"),
  }
end


local function render_html(controls, block)
  local hash = pandoc.sha1(block.text)
  local unique_name = "pseudocode." .. hash .. ".svg"
  local label = string.sub(block.attr.attributes["label"], 2)
  local caption = algorithm_caption(controls, block.attr.attributes["title"])
  create_svg_file(controls, block.text, unique_name)
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


local function check_attributes(attributes)
  -- for key, value in pairs(attributes) do
  --   quarto.log.output(key .. " is " .. value)
  -- end
  return nil
end


local function pseudocode_block_filter(controls)
  local function run_pseudocode_block_filter(block)
    local element
    if not block.attr.classes:includes("pseudocode") then
      element = block
    else
      local attributes = block.attr.attributes
      check_attributes(attributes)
      if attributes["label"] then
        label = string.sub(attributes["label"], 2)
      else
        label = "#none"
      end
      controls.algorithm_counter = controls.algorithm_counter + 1
      if quarto.doc.is_format("pdf") then
        element = render_latex(controls, block)
      else -- html and epub
        element = render_html(controls, block)
      end
    end
    return element
  end

  return { CodeBlock = run_pseudocode_block_filter }
end


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
    debug("Unknown reference '@" .. citation.id .. "'.")
    debug("You can try to do a second pass render to correct it.")
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
    debug("Unknown reference '@" .. citation.id .. "'.")
    debug("You can try to do a second pass render to correct it.")
  end
  return element
end


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


local function initialize_algxpar(meta)
  -- Global controls
  local controls = {
    mode = "file",
    base_path = "",
    algxpar_directory = "_algxpar",
    list_of_references = {},
    chapter_number = "",
    algorithm_counter = 0,
    html_filename = "",
    html_link_prefix = "",
    algorithm_title = "Algorithm",
    algorithm_prefix = "Alg.",
  }

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
    quarto.doc.use_latex_package("algorithm")
    quarto.doc.use_latex_package("algxpar", "brazilian")
    quarto.doc.include_text("before-body",
      "\\floatstyle{plaintop}\\restylefloat{algorithm}")
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


local function debug_print_info(controls)
  debug("")
  debug("algxpar:")
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
  local global_controls = initialize_algxpar(doc.meta)

  -- Render pseudocode and grab labels for references
  doc = doc:walk(pseudocode_block_filter(global_controls))

  -- Process cross references
  doc = doc:walk(process_crossrefs_filter(global_controls))


  -- Update list of references to file
  terminate_algxpar(global_controls)

  -- debug_print_info(global_controls)

  return doc
end


return {
  { Pandoc = algxpar },
}
