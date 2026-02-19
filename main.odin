package luatry

import "core:fmt"
import lua "vendor:lua/5.1"
import "core:c"
import "base:runtime"
import "core:strings"
import os "core:os"
import "core:os/os2"
import "core:sync/chan"
import "core:thread"
import "core:log"
import "core:time"

lua_allocator :: proc "c" (ud: rawptr, ptr: rawptr, osize, nsize: c.size_t) -> (buf: rawptr) {
	old_size := int(osize)
	new_size := int(nsize)
	mem_data := (^Mem_Data)(ud)^
  context = mem_data.ctx^
  (^Mem_Data)(ud).mem_count += nsize

	if ptr == nil {
		data, err := runtime.mem_alloc(new_size)
		return raw_data(data) if err == .None else nil
	} else {
		if nsize > 0 {
			data, err := runtime.mem_resize(ptr, old_size, new_size)
			return raw_data(data) if err == .None else nil
		} else {
			runtime.mem_free(ptr)
			return
		}
	}
}

Mem_Data :: struct {
  ctx: ^runtime.Context,
  mem_count: uint,
}

VM_Command :: enum {
  Halt,
}

start_lua_vm :: proc(commands_chan: chan.Chan(VM_Command, .Recv)) {
  src_path := "lua_src/fib.lua"
  lua_source, lsrc_err := os2.read_entire_file(src_path, context.allocator) 
  if lsrc_err != nil {
    fmt.eprintln(lsrc_err)
    os.exit(1)
  }

  // fmt.println(context)
  _context := context
  fmt.printfln("%#v", _context)
  mem_data := Mem_Data{
    ctx = &_context,
  }
  state := lua.newstate(lua_allocator, &mem_data)
  defer lua.close(state)
  lua.L_openlibs(state)

  lua.L_dostring(state, strings.clone_to_cstring(string(lua_source)))
  str := lua.tostring(state, -1)
  log.debug(str)
  log.debug(mem_data.mem_count)
}

create_threadsafe_queue_logger :: proc() -> (log.Logger, runtime.Allocator_Error) {
  // TODO: make channel here
  MAX_MESSAGES :: 64
  c, err := chan.create(chan.Chan(string), MAX_MESSAGES, context.allocator)
  if err != nil {
    fmt.eprintfln("Couldn't create logger, err: %v", err)
  }

  return log.Logger {
    procedure = threadsafely_log,
    data = new_clone(c),
    lowest_level = .Debug,
    options = {.Level, .Terminal_Color, .Short_File_Path, .Line, .Procedure, .Thread_Id} 
  }, nil
}

threadsafely_log :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: bit_set[runtime.Logger_Option], location := #caller_location) {
  c := cast(^chan.Chan(string))data
  backing: [1024]byte
  buf := strings.builder_from_bytes(backing[:])

  log.do_level_header(options, &buf, level)
  log.do_location_header(options, &buf, location)
  fmt.sbprintf(&buf, "[{}] ", os.current_thread_id())
  fmt.sbprintf(&buf, "%s", text)
  chan.send(c^, strings.to_string(buf))
}

main :: proc() {
  // _context := context
  c, err := chan.create(chan.Chan(VM_Command), context.allocator)
  assert(err == .None)
  defer chan.destroy(c)

  thsafe_logger, logger_err := create_threadsafe_queue_logger()
  if logger_err != nil {
    os.exit(1)
  }

  ctx := runtime.default_context()
  ctx.logger = thsafe_logger
  // c, err := chan.create(chan.Chan(string), context.allocator)
  // assert(err == .None)
  // defer chan.destroy(c)

  lua_thread := thread.create_and_start_with_poly_data(chan.as_recv(c), start_lua_vm, ctx)
  time.sleep(time.Second * 1)

}
