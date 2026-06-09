local tests = {
    "tests/test_module_boot.lua",
}

for _, path in ipairs(tests) do
    dofile(path)
end

print("Integration tests passed")
