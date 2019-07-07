# odin-fs
A zlib licensed single-file package that allows you to iterate over directories.
Currently only works for Win32 since the `core:sys` only supports Windows as of writing. 

## Iterating over directories
You can easily iterate over directories by doing the following:
```
dir, error := open_dir("path/to/dir/");

// Error handling
assert(error == Dir_Error.None);

file: File_Info;
for get_next_file(dir, &file) {
  // ...
  delete_file_info(&file);
}

close_dir(&dir, true);
```

If you however just require an array of all the `File_Info`'s
you can simply call `get_all_files(...)` like so:
```
only_files := true;
recursive  := true;
files, error := get_all_files("path/to/dir/",
                              only_files,
                              recursive,
                              ".txt", ".log");

// Error handling
assert(error == Dir_Error.None);

for file in files {
    fmt.println(get_name(&file));
}

delete_file_info_array(&files);
```

## Other functionality
There are some other functionalities included.
If you want to get parts of a normalized file path you can call these functions:
```
// Make sure the seperators are '/', otherwise call normalize_path(...)
path := "some/path/to/a/file.ext";

// You can also pass a pointer to a File_Info
get_filepath(path); // -> file.ext
get_file(path);     // -> file
get_ext(path);      // -> .ext

```
There is also a `getline` procedure, it simply takes a handle to an open file
and optionally, how big the buffer should be.
```
file, error := os.open("path/to/some/file.txt");
assert(error == os.ERROR_NONE);

should_loop := true;
for should_loop {
  should_loop, line = getline(file);
  defer delete(line);
  
  // ...
}

os.close(file);
```
