package main

import "core:fmt"
import "core:os"
import "core:bytes"
import "core:io"
import "core:strings"
import "core:path/filepath"
// NOTE(rhett): filepath doesn't include a name proc
import "core:path"

// TODO(rhett): Figure out a better way of naming error vairables


//----------------------------------------------------------------
// Constants
//----------------------------------------------------------------
SHOW_DIRECTORY_ERRORS :: false;


//----------------------------------------------------------------
// Structures
//----------------------------------------------------------------
Pack :: struct
    {
    path:         string,
    name:         string,
    total_assets: int,
    total_chunks: int,
    // TODO(rhett): I think we can avoid dynamic here
    assets:       [dynamic]Asset,
    }

Asset :: struct
    {
    name:        string,
    data_offset: u32be,
    data_length: u32be,
    checksum:    u32be,
    }


//----------------------------------------------------------------
// Private Procedures
//----------------------------------------------------------------
@(private)
read_string :: proc(reader: ^bytes.Reader, length: int) -> string
    {
    buffer := make([]u8, length);
    bytes.reader_read(reader, buffer);
    return strings.string_from_ptr(raw_data(buffer), length);
    }

@(private)
read_value :: proc(reader: ^bytes.Reader, $T: typeid) -> T
    {
    // TODO(rhett): Should I free buffer? temp allocator might be enough?
    buffer := make([]u8, size_of(T), context.temp_allocator);
    bytes.reader_read(reader, buffer);
    return (^T)(raw_data(buffer))^;
    }

@(private)
create_multiple_directories :: proc(elems: ..string) -> (output_path: string, success: bool)
    {
    for elem, _ in elems
        {
        if elem == ""
            {
            fmt.eprintln("Invalid directory element name.");
            return "", false;
            }

        output_path = path.join(elems={output_path, elem});

        // NOTE(rhett): 2nd return indicates if a new allocation was made
        ok := os.make_directory(output_path, 0);
        if ok == 0
            {
            when SHOW_DIRECTORY_ERRORS
                {
                // TODO(rhett): Figure out how to get the error code
                fmt.eprintln("make_directory error:", ok);
                }
            }
        }

    return output_path, true;
    }


//----------------------------------------------------------------
// Public Procedures
//----------------------------------------------------------------
load_pack_from_file :: proc(reader: ^bytes.Reader, buffer: []u8, pack_path: string) -> (pack: Pack, success: bool)
    {
    clean_path, _ := filepath.to_slash(pack_path);

    buffer, ok := os.read_entire_file(clean_path);
    if !ok
        {
        fmt.eprintln("Unable to read pack file.");
        return {}, false;
        }

    pack.path = clean_path;
    pack.name = path.name(pack.path);

    bytes.reader_init(reader, buffer);
    for
        {
        next_chunk := read_value(reader, u32be);
        asset_count := read_value(reader, u32be);

        pack.total_chunks += 1;
        for i := 0; i < cast(int)asset_count; i += 1
            {
            pack.total_assets += 1;

            name_length := read_value(reader, u32be);

            asset: Asset;

            using asset;
            name = read_string(reader, int(name_length));
            data_offset = read_value(reader, u32be);
            data_length = read_value(reader, u32be);
            checksum = read_value(reader, u32be);

            append(&pack.assets, asset);
            }

        if next_chunk == 0 do break;
        bytes.reader_seek(reader, cast(i64)next_chunk, io.Seek_From.Start);
        }

    return pack, true;
    }

unpack_pack_to_folder :: proc(pack: Pack, reader: ^bytes.Reader, output_folder: string) -> (success: bool)
    {
    output_folder_path, ok := create_multiple_directories(output_folder, pack.name);
    if !ok
        {
        return;
        }
    defer delete(output_folder_path);

    for a in pack.assets
        {
        asset_buffer := make([]u8, a.data_length);
        output_asset_path := path.join(output_folder_path, a.name);
        /*  FIXME(rhett):
            This defer will cause odin to fail building
                this file without giving any output.
        */
        // defer delete(asset_buffer);

        bytes.reader_read_at(reader, asset_buffer, cast(i64)a.data_offset);
        success := os.write_entire_file(output_asset_path, asset_buffer);
        if !success
            {
            // NOTE(rhett): Let the OS handle cleanup
            fmt.eprintln("Unable to write asset to file.");
            return false;
            }

        // HACK(rhett): Workaround for Odin defer bug
        delete(output_asset_path);
        delete(asset_buffer);
        }

    return true;
    }


//----------------------------------------------------------------
// Main Procedure
//----------------------------------------------------------------
main :: proc()
    {
    example_path := `D:\WindowsUsers\Rhett\Desktop\PlanetSide 2 Beta\Resources\Assets\Assets_000.pack`;

    fmt.println("Loading", example_path);

    pack_reader: bytes.Reader;
    pack_buffer: []u8;
    my_pack, success := load_pack_from_file(&pack_reader, pack_buffer, example_path);
    if !success
        {
        fmt.eprintln("Unable to load pack.");
        return;
        }
    defer delete(pack_buffer);

    fmt.println("Extracting assets...");
    ok := unpack_pack_to_folder(my_pack, &pack_reader, "output");
    if !ok
        {
        fmt.eprintln("Unable to extract assets from pack.");
        return;
        }
    fmt.println("Extraction complete!");
    }
