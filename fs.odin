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
//  delete_file_info_array(...)
//    Frees a dynamic array of File_Info's
//
//  open_dir(...)
//    Returns the Dir_Info and also opens a handle which allows iterating.
//    Needs to be closed with close_dir(...)
//
//  close_dir(...)
//    Closes the handle on the Dir_Info, optionally frees the Dir_Info.
//
//  delete_dir_info(...)
//    Frees the Dir_Info.
//
//  get_dir_info(...)
//    Opens the directory, gets the Dir_Info and then closes it again.
//
//  get_next_file(...)
//    Iterates over the next file in an open Dir_Info and fills out the
//    File_Info pointer. Returns true while there are files to scan.
//
//  delete_file_info(...)
//    Frees the File_Info.
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
//  normalize_path(...)
//    Takes a string to a path and normalizes the slashes to '/' and returns it.
//
//  getline(...)
//    Gets the next line in a file, returns true while the file has not been fully read.
//
// Examples:
//  Iterating over directories:
//   
//   dir, error := open_dir("path/to/dir/");
//   
//   // Error handling
//   assert(error == Dir_Error.None);
//   
//   file: File_Info;
//   for get_next_file(dir, &file) {
//       fmt.println(get_name(&file));
//       delete_file_info(&file);
//   }
//   
//   close_dir(&dir, true);
//   
//  Getting all the .txt and .log files recursively:
//   
//   only_files := true;
//   recursive  := true;
//   files, error := get_all_files("path/to/dir/",
//                                 only_files,
//                                 recursive,
//                                 ".txt", ".log");
//
//   // Error handling
//   assert(error == Dir_Error.None);
//
//   for file in files {
//       fmt.println(get_name(&file));
//   }
//   
//   delete_file_info_array(&files);
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
//   exts: pointer to an array of the file extensions
get_all_files :: proc(path: string, only_files: bool, recursive: bool, exts: ..string) -> ([dynamic]File_Info, Dir_Error) {
    npath := normalize_path(path);
    defer delete(npath);
    
    files: [dynamic]File_Info;
    
    error := append_all_files(npath, only_files, recursive, &files, ..exts);
    
    if error != Dir_Error.None {
        delete(files);
        return nil, error;
    }
    
    return files, Dir_Error.None;
}

// Opens a directory and gets the directory info
open_dir :: proc(path: string) -> (dir: Dir_Info, error: Dir_Error) {
    npath := normalize_path(path);
    defer delete(npath);
    
    dir.path = strings.clone(npath);
    
    // Add wildcard
    if !strings.has_suffix(npath, "*") {
        old_path := npath;
        npath = strings.concatenate({ npath, "*" });
        delete(old_path);
    }
    
    find_data: win32.Find_Data_A;
    cpath := strings.clone_to_cstring(npath);
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
close_dir :: proc(dir: ^Dir_Info, delete_info := true) {
    if dir.handle != win32.INVALID_HANDLE {
        // assert(cast(bool) win32.find_close(dir.handle));
        dir.handle = win32.INVALID_HANDLE;
    }
    
    if delete_info do delete_dir_info(dir);
}

delete_dir_info :: proc(dir: ^Dir_Info) {
    delete(dir.path);
}

// Opens the directory and gets all the info and then closes it again
get_dir_info :: proc(path: string) -> (Dir_Info, Dir_Error) {
    dir, error := open_dir(path);
    
    if error != Dir_Error.None do return ---, error;
    
    if error == Dir_Error.None {
        close_dir(&dir, false);
    }
    
    return dir, Dir_Error.None;
}

// Fills out the info with the data of the next file
get_next_file :: proc(dir: Dir_Info, info: ^File_Info) -> bool {
    if dir.handle == win32.INVALID_HANDLE do return false;
    // assert(dir.handle != win32.INVALID_HANDLE);
    
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

delete_file_info :: proc(info: ^File_Info) {
    delete(info.path);
}

delete_file_info_array :: proc(files: ^[dynamic]File_Info) {
    for i in 0..<len(files) {
        delete_file_info(&(files^)[i]);
    }
    delete(files^);
}

// Returns the filename of a normalized path
//   "output/data/file.txt" -> "file.txt"
//   "output/data/folder/"  -> "folder"
get_filename :: proc {get_filename_from_string, get_filename_from_info};

// Returns the name of a normalized path
//   "output/data/file.txt" -> "file"
//   "output/data/folder/"  -> "folder"
get_name :: proc {get_name_from_string, get_name_from_info};

// Returns the extension of a normalized path
//   "output/data/file.txt" -> ".txt"
//   "output/data/folder/"  -> ""
get_ext :: proc {get_ext_from_string, get_ext_from_info};

get_filename_from_string :: proc(path: string) -> string {
    filename := path;

    // Get rid of the trailing slash
    if filename[len(filename) - 1] == '/' {
        filename = filename[:len(filename) - 1];
    }
    
    index := strings.last_index_any(filename, "/");
    
    if (index == -1) {
        return filename[:];
    }
    
    return filename[index + 1:];
}

get_filename_from_info :: proc(info: ^File_Info) -> string {
    return get_filename_from_string(info.path);
}

get_ext_from_string :: proc(path: string) -> string {
    filename := get_filename(path);
    
    index := strings.last_index_any(filename, ".");
    
    if (index == -1) {
        return filename[:];
    }
    
    return filename[index:len(filename)];
}

get_ext_from_info :: proc(info: ^File_Info) -> string {
    if info.is_directory do return "";

    filename := get_filename(info);
        
    // Get filename seperator
    index := strings.last_index_any(filename, ".");
    
    if (index == -1) {
        return filename[:];
    }
    
    return filename[index:];
}

get_name_from_string :: proc(path: string) -> string {
    filename := get_filename(path);

    // Get filename seperator
    index := strings.last_index_any(filename, ".");
    
    if (index == -1) {
        return filename[:];
    }
    
    return filename[:index];
}

get_name_from_info :: proc(info: ^File_Info) -> string {
    filename := get_filename(info);
    
    if info.is_directory do return filename;
    
    // Get filename seperator
    index := strings.last_index_any(filename, ".");
    
    if (index == -1) {
        return filename[:];
    }
    
    return filename[:index];
}

// Gets the next line in a file
//   file: a handle to a file
//   buffer_size: the buffer of every read. A bigger buffer is faster but costs more memory.
//   Returns false if the file has been read and also returns the actual line
getline :: proc(file: os.Handle, buffer_size: int = 32) -> (bool, string) {
    if buffer_size <= 0 do return false, strings.clone("");

    buf := make([]u8, buffer_size);
    defer if buf != nil do delete(buf);
    line: string;
    
    should_read := buf != nil;
    for should_read {
        bytes_read, error := os.read(file, buf);
        str := strings.string_from_ptr(auto_cast &buf[0], bytes_read);
        
        // @TODO: error reporting
        if error != os.ERROR_NONE {
            return false, ---;
        }
        
        // Find any line endings
        index := strings.index_any(str, "\r\n");
        
        // @HACK: Sometimes the buffer will only read the \r of the \r\n
        // and will cause it to read an extra empty line.
        //
        // A hacky workaround is if it ends in \r and that is also the newline
        // we found, just pretend we didn't find any line endings at all so
        // it will read another buffer's worth and hopefully resolve the slicing.
        if len(str) > 0 && str[len(str) - 1] == '\r' && len(str) - 1 == index {
            index = -1;
        }
        
        if index == -1 {
            old_line := line;
            line = strings.concatenate({ line, str });
            delete(old_line);
        } else {
            eol := 1;
            
            // If we have \r\n we need to offset by 2 characters
            if len(str) > index + 1 && (str[index] == '\r' && str[index+1] == '\n') do eol = 2;
            
            old_line := line;
            line = strings.concatenate({ line, str[:index] });
            delete(old_line);
            
            // Seek back to line start
            offset: i64 = i64(index) - i64(bytes_read) + i64(eol);
            os.seek(file, offset, 1 /* win32.FILE_CURRENT */);
            return true, line;
        }
        
        if bytes_read == 0 do return false, line;
    }

    return false, line;
}
    
// Normalizes all the seperators in a path to '/', returns newly allocated normalized path
normalize_path :: proc(path: string) -> string {
    // Normalize slashes
    npath, was_allocated := strings.replace_all(path, "\\", "/");
    
    // Add last slash
    if !strings.has_suffix(npath, "/") {
        old_path := npath;
        npath = strings.concatenate({ npath, "/" });
        
        if was_allocated do delete(old_path);
        was_allocated = true;
    }
    
    return (was_allocated) ? npath : strings.clone(npath);
}

@private
append_all_files :: proc(path: string, only_files: bool, search_subdirs: bool, files: ^[dynamic]File_Info, exts: ..string) -> Dir_Error {
    npath := normalize_path(path);
    defer delete(npath);
    
    dir, error := open_dir(npath);
    
    defer if error == Dir_Error.None do close_dir(&dir);
    
    // @TODO: we should probably also return the faulty directory
    if error != Dir_Error.None do return error;
        
    info: File_Info;
    for get_next_file(dir, &info) {
        filename := get_filename(&info);
        ext      := get_ext(&info);
        
        // defer delete(filename);
        // defer delete(ext);
        
        if !only_files || (only_files && !info.is_directory) {
            // Don't add directories like . or ..
            valid_dir  := info.is_directory && filename[0] != '.';
            
            contains_ext := false;
            if len(ext) > 0 {
                for e in exts {
                    if (e == ext[1:]) {
                        contains_ext = true;
                        break;
                    }
                }
            }
            
            valid_file := len(exts) == 0 || (len(ext) > 0 && contains_ext);
            
            if valid_dir || (!info.is_directory && valid_file) {
                append(files, info);
            } else {
                delete_file_info(&info);
            }
        }
        
        if search_subdirs && info.is_directory && filename[0] != '.' {
            error = append_all_files(info.path, only_files, search_subdirs, files, ..exts);
            
            if error != Dir_Error.None do return error;
        }
    }
    
    return Dir_Error.None;
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
