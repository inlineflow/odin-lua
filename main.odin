package luatry

import "core:fmt"
import lua "vendor:lua/5.1"
import "core:c"
import "base:runtime"
import "core:strings"
import os "core:os/os2"
import "core:sync/chan"
import "core:thread"


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

start_lua_vm :: proc(commands_chan: chan.Chan(VM_Command, .Recv), log_chan: chan.Chan(string, .Send)) {
  src_path := "lua_src/fib.lua"
  lua_source, lsrc_err := os.read_entire_file(src_path, context.allocator) 
  if lsrc_err != nil {
    fmt.eprintln(src_path)
    os.exit(1)
  }

  _context := context
  mem_data := Mem_Data{
    ctx = &_context,
  }
  state := lua.newstate(lua_allocator, &mem_data)
  defer lua.close(state)
  lua.L_openlibs(state)

  lua.L_dostring(state, strings.clone_to_cstring(string(lua_source)))
  str := lua.tostring(state, -1)
  fmt.println(str)
  fmt.println(mem_data.mem_count)
}

main :: proc() {
  // _context := context
  c, err := chan.create(chan.Chan(VM_Command), context.allocator)
  assert(err == .None)
  defer chan.destroy(c)

  c, err := chan.create(chan.Chan(string), context.allocator)
  assert(err == .None)
  defer chan.destroy(c)

  lua_thread := thread.create_and_start_with_poly_data2(chan.as_recv(c), start_lua_vm)
}
