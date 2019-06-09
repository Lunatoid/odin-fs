
//
// License:
//  See end of the file for license information.
//
// API:
//  get_all_files(...)
//    Creates a dynamic array of File_Info's of a directory.
//    Has options to scan recursively and to only include files with certain
//    extensions.
//
//  open_dir(...)
//    Returns the Dir_Info and also opens a handle which allows iterating.
//    Needs to be closed with close_dir(...)
//
//  close_dir(...)
//    Closes the handle on the Dir_Info
//
//  get_dir_info(...)
//    Opens the directory, gets the Dir_Info and then closes it again.
//
//  get_next_file(...)
//    Iterates over the next file in an open Dir_Info and fills out the
//    File_Info pointer. Returns true while there are files to scan.
//
//  get_filename(...)
//    Returns the filename of a path.
//
//  get_name(...)
//    Returns the filename without the extension
//
//  get_ext(...)
//    Returns the filename with only the extension (including the '.')
//
// Examples:
//  Iterating over directories:
//   
//   dir, error := open_dir("C:/Directory/");
//   
//   // Error handling
//   assert(error == Dir_Error.None);
//   
//   file: File_Info;
//   for get_next_file(dir, &file)
//       fmt.println(get_name(&file));
//   }
//   
//   close_dir(&dir);
//   
//  Getting all the .txt and .log files recursively:
//   
//   only_files := true;
//   recursive  := true;
//   files, error := get_all_files("C:/Directory",
//                                 only_files,
//                                 recursive,
//                                 ".txt.log");
//
//   // Error handling
//   assert(error == Dir_Error.None);
//
//   for file in files {
//       fmt.println(get_name(&file));
//   }
//   
//   delete(files);
//

package fs;

import "core:os"
import "core:strings"
import "core:time"

// Right now the core:sys only has win32
// @TODO: update for other OS' when they're supported in core:sys
#assert(os.OS == "windows");

// Import correct system bindings
when os.OS == "windows" {
    import "core:sys/win32"
}

Dir_Info :: struct {
    path:             string,
    handle:           win32.Handle,
    
    creation_time:    time.Time,
    last_access_time: time.Time,
    last_write_time:  time.Time,
}

File_Info :: struct {
    path:             string,
    creation_time:    time.Time,
    last_access_time: time.Time,
    last_write_time:  time.Time,
    file_size:        u64,
    
    is_directory:     bool,
}

Dir_Error :: enum {
    None,
    CantOpen,
    NotDir,
}

// Creates a dynamic array of all the files
//   only_files: whether or not to exclude directories from the files
//   recursive: whether or not to get all the files recursively
//   exts: extension filter, "" for all files, ".txt.md" will only include .txt and .md files
get_all_files :: proc(path: string, only_files: bool, recursive: bool, exts := "") -> ([dynamic]File_Info, Dir_Error) {
    path = normalize_path(path);
    files: [dynamic]File_Info;
    
    error := append_all_files(path, only_files, recursive, &files, exts);
    
    if error != Dir_Error.None {
        delete(files);
        return nil, error;
    }
    
    return files, Dir_Error.None;
}

// Opens a directory and gets the directory info
open_dir :: proc(path: string) -> (dir: Dir_Info, error: Dir_Error) {
    path = normalize_path(path);
    dir.path = path;
    
    // Add wildcard
    if !strings.has_suffix(path, "*") {
        path = strings.concatenate({ path, "*" });
    }
    
    find_data: win32.Find_Data_A;
    cpath := strings.clone_to_cstring(path);
    dir.handle = win32.find_first_file_a(cpath, &find_data);
    
    if dir.handle == win32.INVALID_HANDLE {
        return ---, Dir_Error.CantOpen;  
    }
    
    if find_data.file_attributes & win32.FILE_ATTRIBUTE_DIRECTORY == 0 {
        return ---, Dir_Error.NotDir;
    }
    
    dir.creation_time    = filetime_to_time(find_data.creation_time);
    dir.last_access_time = filetime_to_time(find_data.last_access_time);
    dir.last_write_time  = filetime_to_time(find_data.last_write_time);
    
    return;
}

// Closes the handle
close_dir :: proc(dir: ^Dir_Info) {
    if dir.handle != win32.INVALID_HANDLE {
        assert(cast(bool) win32.find_close(dir.handle));
        dir.handle = win32.INVALID_HANDLE;
    } 
}

// Opens the directory and gets all the info and then closes it again
get_dir_info :: proc(path: string) -> (Dir_Info, Dir_Error) {
    dir, error := open_dir(path);
    
    if error != Dir_Error.None do return ---, error;
    
    if error == Dir_Error.None {
        close_dir(&dir);
    }
    
    return dir, Dir_Error.None;
}

// Fills out the info with the data of the next file
get_next_file :: proc(dir: Dir_Info, info: ^File_Info) -> bool {
    // if dir.handle == win32.INVALID_HANDLE do return false;
    assert(dir.handle != win32.INVALID_HANDLE);
    
    find_data: win32.Find_Data_A;
    more := cast(bool) win32.find_next_file_a(dir.handle, &find_data);
    
    cstr_name := cast(cstring)&find_data.file_name[0];
    
    info.path = strings.concatenate({ dir.path, string(cstr_name) });
    info.creation_time    = filetime_to_time(find_data.creation_time);
    info.last_access_time = filetime_to_time(find_data.last_access_time);
    info.last_write_time  = filetime_to_time(find_data.last_write_time);
    
    info.file_size = u64(find_data.file_size_low) | u64(find_data.file_size_high) << 32;
    
    info.is_directory = find_data.file_attributes & win32.FILE_ATTRIBUTE_DIRECTORY != 0;
    
    return more;
}

// Returns the filename of a path
//   "output/data/file.txt" -> "file.txt"
//   "output/data/folder/"  -> "folder"
get_filename :: proc {get_filename_from_string, get_filename_from_info};

// Returns the name of a path
//   "output/data/file.txt" -> "file"
//   "output/data/folder/"  -> "folder"
get_name :: proc {get_name_from_string, get_name_from_info};

// Returns the extension of a path
//   "output/data/file.txt" -> ".txt"
//   "output/data/folder/"  -> ""
get_ext :: proc {get_ext_from_string, get_ext_from_info};

get_filename_from_string :: proc(path: string) -> string {
    path = normalize_path(path);
    
    // Get rid of the trailing slash
    if path[len(path) - 1] == '/' {
        path = path[:len(path) - 1];
    }
    
    index := strings.last_index_any(path, "/");
    
    if (index == -1) {
        return path;
    }
    
    return path[index + 1:];
}

get_filename_from_info :: proc(info: ^File_Info) -> string {
    return get_filename_from_string(info.path);
}

get_ext_from_string :: proc(path: string) -> string {
    filename := get_filename(path);
    
    index := strings.last_index_any(filename, ".");
    
    if (index == -1) {
        return filename;
    }
    
    return filename[index:len(filename)];
}

get_ext_from_info :: proc(info: ^File_Info) -> string {
    if info.is_directory do return "";

    filename := get_filename(info);
        
    // Get filename seperator
    index := strings.last_index_any(filename, ".");
    
    if (index == -1) {
        return filename;
    }
    
    return filename[index:];
}

get_name_from_string :: proc(path: string) -> string {
    filename := get_filename(path);

    // Get filename seperator
    index := strings.last_index_any(filename, ".");
    
    if (index == -1) {
        return filename;
    }
    
    return filename[:index];
}

get_name_from_info :: proc(info: ^File_Info) -> string {
    filename := get_filename(info);
    
    if info.is_directory do return filename;
    
    // Get filename seperator
    index := strings.last_index_any(filename, ".");
    
    if (index == -1) {
        return filename;
    }
    
    return filename[:index];
}

@private
append_all_files :: proc(path: string, only_files: bool, search_subdirs: bool, files: ^[dynamic]File_Info, exts: string) -> Dir_Error {
    path = normalize_path(path);
    dir, error := open_dir(path);
    
    defer if error == Dir_Error.None do close_dir(&dir);
    
    // @TODO: we should probably also return the faulty directory
    if error != Dir_Error.None do return error;
        
    info: File_Info;
    for get_next_file(dir, &info) {
        if !only_files || (only_files && !info.is_directory) {
            // Don't add directories like . or ..
            filename := get_filename(&info);
            ext      := get_ext(&info);
            
            valid_dir  := info.is_directory && filename[0] != '.';
            valid_file := exts == "" || (exts != "" && strings.contains(exts, ext));
            
            if valid_dir || (!info.is_directory && valid_file) {
                append(files, info);
            }
        }
        
        if search_subdirs && info.is_directory && get_filename(&info)[0] != '.' {
            error = append_all_files(info.path, only_files, search_subdirs, files, exts);
            
            if error != Dir_Error.None do return error;
        }
    }
    
    return Dir_Error.None;
}


@private
normalize_path :: proc(path: string) -> string {
    // Normalize slashes
    path, _ = strings.replace_all(path, "\\", "/");
    
    // Add last slash
    if !strings.has_suffix(path, "/") {
        path = strings.concatenate({ path, "/" });
    }
    
    return path;
}

// Modified version of now() in core:sys/time_windows
@private
filetime_to_time :: proc(file_time: win32.Filetime) -> time.Time {
    quad := u64(file_time.lo) | u64(file_time.hi) << 32;
    
    UNIX_TIME_START :: 0x019db1ded53e8000;
    
    ns := (1e9/1e7)*(i64(quad) - UNIX_TIME_START);
    return time.Time{_nsec=ns};
}

// ZLIB LICENSE
//  
//  Copyright (c) 2019 Tom Mol
//  
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software.
//  
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//  
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source distribution.
//