package main

import "core:fmt"
import "core:os"

import "fs"

main :: proc() {
    // Recursively get all the .exe, .dll and .lib files and then print them out
    if len(os.args) <= 1 {
        fmt.printf("Usage: %v <directory>", os.args[1]);
        return;
    }
    
    files, error := fs.get_all_files(os.args[1], true, true, ".exe.dll.lib");
    defer if error == fs.Dir_Error.None do fs.delete_file_info_array(files);
    
    for f in files {
        fmt.printf(" %v\n", f.path);
    }
}
