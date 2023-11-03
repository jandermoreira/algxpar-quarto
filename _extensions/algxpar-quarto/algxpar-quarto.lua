--[[
  Lua filter: replace a pseudocode block with a SVG image created with LaTeX
  Moreira, J. 2023
]]

-- json.lua
-- https://github.com/craigmj/json4lua
local json = require 'json'



local debug = quarto.log.output
local stringify = pandoc.utils.stringify

local function startsWith(text, subtext)
  return string.sub(text, 1, 4) == subtext
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
    \AlgSet{language = brazilian}
    \begin{minipage}{15cm}
    %s
    \end{minipage}
  \end{document}
]]

local function create_svg_file(pseudocode_text, filename)
  debug(">> Ensure " .. algxpar_directory .. " with " .. filename)
  pandoc.system.make_directory(algxpar_directory, true)
  pandoc.system.with_temporary_directory(
    "algxpar",
    function(temporary_directory)
      pandoc.system.with_working_directory(
        temporary_directory,
        function()
          print(">> SVG in " .. pandoc.system.get_working_directory())
          svg_filename = project_directory .. "/" ..
              algxpar_directory .. "/" .. filename
          print(">> SVG file: " .. svg_filename)
          local tex_file = io.open("pseudocode.tex", "w")
          if tex_file ~= nil then
            tex_file:write(latex_code_template:format(pseudocode_text))
            tex_file:close()
          end
          os.execute("pdflatex -interaction=nonstopmode " ..
            "pseudocode.tex > /dev/null")
          os.execute("pdf2svg pseudocode.pdf " .. svg_filename)
          return nil
        end
      )
      return nil
    end
  )
  print(">> SVG: done")
end


local function render_latex(block)
  label = string.sub(block.attr.attributes["label"], 2)
  return {
    pandoc.RawInline("latex", "\\begin{algorithm}"),
    pandoc.RawInline("latex", "\\caption{Este é um algoritmo}"),
    pandoc.RawInline("latex", "\\label{" .. label .. "}"),
    pandoc.RawInline("latex", block.text),
    pandoc.RawInline("latex", "\\end{algorithm}"),
  }
end

local function render_html(block)
  local hash = pandoc.sha1(block.text)
  local unique_name = "pseudocode." .. hash .. ".svg"
  local label = string.sub(block.attr.attributes["label"], 2)
  create_svg_file(block.text, unique_name)
  element = pandoc.Div(
    {
      pandoc.Para("Algoritmo " .. chapter_number .. algorithm_counter),
      pandoc.Para({
        pandoc.Image(
          {},
          "/" .. algxpar_directory .. "/" .. unique_name,
          "",
          ---@diagnostic disable-next-line: missing-fields
          { width = "95%" })
      })
    },
    ---@diagnostic disable-next-line: missing-fields
    { id = label }
  )
  list_of_references[label] = {
    label = "Algoritmo " .. chapter_number .. algorithm_counter,
    caption = "",
    file = html_filename,
    target = '#' .. label,
    title = "",
  }
  return element
end


local function render_pseudocode_block(block)
  local element
  if not block.attr.classes:includes("pseudocode") then
    -- default: do nothing
    element = block
  else
    -- handle pseudocode block
    local attributes = block.attr.attributes
    local label = string.sub(attributes["label"], 2) or "NULL"
    algorithm_counter = algorithm_counter + 1
    if quarto.doc.is_format("pdf") then
      element = render_latex(block)
    else
      -- html and epub
      element = render_html(block)
    end
  end
  return element
end


local function cite_latex(label)
  return pandoc.RawInline("latex",
    "Algoritmo~" .. chapter_number .. "\\ref{" .. label .. "}")
end


local function cite_html(citation)
  local element
  if list_of_references[citation.id] then
    local target = link_prefix ..
        list_of_references[citation.id].file ..
        list_of_references[citation.id].target
    local link = pandoc.Link(
      list_of_references[citation.id].label,
      target,
      list_of_references[citation.id].title
    )
    element = link
  else
    element = pandoc.Str("??" .. citation.id)
    debug("Unknown reference '@" .. citation.id .. "'.")
    debug("You can try to do a second pass render to correct it.")
  end
  return element
end


local function cite_plain(citation)
  local element
  if list_of_references[citation.id] then
    element = pandoc.Str("Algoritmo " ..
      list_of_references[citation.id].label)
  else
    element = pandoc.Str("??" .. citation.id)
    debug("Unknown reference '@" .. citation.id .. "'.")
    debug("You can try to do a second pass render to correct it.")
  end
  return element
end


local function process_crossrefs(citation)
  local element = citation
  for _, single_citation in pairs(citation.citations) do
    if startsWith(single_citation.id, "alg-") then
      if quarto.doc.is_format("pdf") then
        element = cite_latex(single_citation.id)
      elseif quarto.doc.is_format("html") then
        element = cite_html(single_citation)
      else
        element = cite_plain(single_citation)
      end
    end
  end
  return element
end


local function initialize_list_of_references()
  local list
  if not is_project then
    list = {}
  else
    algxpar_path = project_directory .. "/" .. algxpar_directory
    pandoc.system.make_directory(algxpar_path, true)
    pandoc.system.with_working_directory(
      algxpar_path,
      function()
        local filename = "references.json"
        local file = io.open(filename, "r")
        if file == nil then
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


local function initialize(meta)
  quarto_filename = quarto.doc.input_file
  is_project = os.getenv("QUARTO_PROJECT_DIR") ~= nil
  if not is_project then
    project_directory = ""
    algxpar_directory = "_algxpar"
  else
    project_directory = os.getenv("QUARTO_PROJECT_DIR")
    quarto_filename = string.sub(quarto_filename, #project_directory + 2)
    algxpar_directory = "_algxpar"
  end


  chapter_number = ""
  local _, directoryLevel = quarto_filename:gsub("/", "")
  if meta["book"] then
    for _, render in pairs(meta["book"]["render"]) do
      if render["file"] and render["number"] and
          stringify(render["file"]) == quarto_filename then
        chapter_number = stringify(render["number"]) .. "."
      end
    end
  end

  link_prefix = ""
  if quarto.doc.is_format("html") then
    html_filename = quarto_filename:gsub("%.qmd$", ".html")
    for _ = 1, directoryLevel do
      link_prefix = "../" .. link_prefix
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

  list_of_references = initialize_list_of_references()
  algorithm_counter = 0

  debug("")
  debug("algxpar:")
  debug("  current file: " .. quarto_filename)
  if is_project then
    debug("  mode: project")
    debug("  project directory: " .. project_directory)
    debug("  chapter prefix: " .. chapter_number)
  else
    debug("  mode: single file")
  end
  debug("  algxpar directory: " .. algxpar_directory)
  if quarto.doc.is_format("html") then
    debug("  links to: " .. html_filename)
    debug("  root is in: " .. link_prefix)
  end
  debug("  list of references size: " .. #list_of_references)
  debug("")

  return meta
end


local function save_references()
  if is_project then
    pandoc.system.with_working_directory(
      project_directory .. "/_algxpar",
      function()
        local referenceFile = "references.json"
        file = io.open(referenceFile, "w")
        if file ~= nil then
          file:write(json.encode(list_of_references))
          file:close()
        end
        return nil
      end
    )
  end
end


return {
  { Meta = initialize },
  { CodeBlock = render_pseudocode_block },
  { Cite = process_crossrefs },
  { Meta = save_references },
}