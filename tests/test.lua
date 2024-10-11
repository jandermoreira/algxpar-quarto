-- test.lua



local function run_c(block)
    local list_of_blocks = { block }
    if block.attr.classes:includes("{c}", "c") then
        pandoc.system.with_temporary_directory(
            "running_c",
            function(temporary_directory)
                pandoc.system.with_working_directory(
                    temporary_directory,
                    function()
                        list_of_blocks = { create_source_code_block(block.text) }
                        local compilation_result_block = create_compilation_result_block(block.text)
                        if compilation_result_block then
                            table.insert(list_of_blocks, compilation_result_block)
                        end
                        local execution_result_block = create_execution_result_block(block.text)
                        if execution_result_block then
                            table.insert(list_of_blocks, execution_result_block)
                        end
                        return nil
                    end
                )
                return nil
            end
        )
    end
    return list_of_blocks
end



return {
    { CodeBlock = run_c }
}
