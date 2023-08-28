package regexp

import sa "core:container/small_array"
import "core:strings"
import "core:runtime"
import "core:unicode/utf8"

Pattern :: struct {
	initial_state: ^NFA_State,
}

Error :: union {
	Regexp_Error,
	runtime.Allocator_Error,
}

Regexp_Error :: struct {
	type: enum{
		Dangling_Quantifier = 1,
		Invalid_Escape,
	},
	position: int,
}

compile :: proc(expr: string, allocator := context.allocator) -> (Pattern, Error) {
	context.allocator = allocator

	Fragment :: struct {
		first_state: ^NFA_State,
		ends: [dynamic]^NFA_State,
	}

	new_ends :: proc(states: ..^NFA_State) -> [dynamic]^NFA_State {
		ends := make([dynamic]^NFA_State, context.temp_allocator)
		append(&ends, ..states)
		return ends
	}

	link :: proc(ends: []^NFA_State, state: ^NFA_State) {
		for end_ptr in ends {
			switch end_state in end_ptr {
				case NFA_Rune:
					end_state.next = state
					end_ptr^ = end_state
				case NFA_Begin_Capture:
					end_state.next = state
					end_ptr^ = end_state
				case NFA_End_Capture:
					end_state.next = state
					end_ptr^ = end_state
				case NFA_Split:
					end_state.options[1] = state
					end_ptr^ = end_state
				case NFA_Accept:
					panic("unreachable code")
			}
		}
	}

	rune_node :: proc(frag: ^Fragment, rm: Rune_Matcher) -> (Fragment, []^NFA_State) {
		state := new(NFA_State)
		state^ = NFA_Rune{ matches = rm }
		if frag.first_state == nil {
			frag.first_state = state
			frag.ends = new_ends(state)
			return { state, frag.ends }, nil
		} else {
			link(frag.ends[:], state)
			last_linked_ends := frag.ends[:]
			frag.ends = new_ends(state)
			return { state, frag.ends }, last_linked_ends
		}
	}

	compile_fragment :: proc(expr: string) -> (frag: Fragment, err_all: Error) {
		last_linked_ends: []^NFA_State
		subfrag: Fragment  // latest piece of the fragment which is linked by quantifiers (?, *, +, {n,m})

		defer if err_all != nil {
			destroy_nfa(frag.first_state)
		}

		skip := 0
		for r, i in expr {
			if skip > 0 {
				skip -= 1
				continue
			}

			switch r {
				case '(': panic("not implemented")
				case '|': panic("not implemented")

				case '?':
					if subfrag.first_state == nil {
						return {}, Regexp_Error{.Dangling_Quantifier, i}
					}
					state := new(NFA_State)
					state^ = NFA_Split{ {subfrag.first_state, nil} }
					if last_linked_ends != nil {
						link(last_linked_ends, state)
					} else {
						frag.first_state = state
					}
					append(&frag.ends, state)
					subfrag = {nil, nil}

				case '*':
					if subfrag.first_state == nil {
						return {}, Regexp_Error{.Dangling_Quantifier, i}
					}
					state := new(NFA_State)
					state^ = NFA_Split{ {subfrag.first_state, nil} }
					link(subfrag.ends[:], state)
					if last_linked_ends != nil {
						link(last_linked_ends, state)
						last_linked_ends = nil
					} else {
						frag.first_state = state
					}
					frag.ends = new_ends(state)
					subfrag = {nil, nil}

				case '+':
					if subfrag.first_state == nil {
						return {}, Regexp_Error{.Dangling_Quantifier, i}
					}
					state := new(NFA_State)
					state^ = NFA_Split{ {subfrag.first_state, nil} }
					link(subfrag.ends[:], state)
					frag.ends = new_ends(state)
					subfrag = {nil, nil}

				case '[': panic("not implemented")
				case '\\':
					skip = 1
					switch next_r := utf8.rune_at(expr, i + utf8.rune_size(r)); next_r {
						case '\\', '[', ']', '(', ')', '{', '}', '+', '*', '?', '^', '$':
							subfrag, last_linked_ends = rune_node(&frag, {runes = next_r})

						case 'd':
							subfrag, last_linked_ends = rune_node(&frag, {runes = Rune_Class.Number})
						case 'D':
							subfrag, last_linked_ends = rune_node(&frag, {runes = Rune_Class.Number, invert = true})

						case 'w':
							subfrag, last_linked_ends = rune_node(&frag, {runes = Rune_Class.Word})
						case 'W':
							subfrag, last_linked_ends = rune_node(&frag, {runes = Rune_Class.Word, invert = true})

						case 's':
							subfrag, last_linked_ends = rune_node(&frag, {runes = Rune_Class.Space})
						case 'S':
							subfrag, last_linked_ends = rune_node(&frag, {runes = Rune_Class.Space, invert = true})

						case:
							return {}, Regexp_Error{ .Invalid_Escape, i }
					}

				case '.':
					subfrag, last_linked_ends = rune_node(&frag, {runes = Rune_Class.Any})

				case:
					subfrag, last_linked_ends = rune_node(&frag, {runes = r})
			}
		}

		return frag, nil
	}

	final_frag, err := compile_fragment(expr)
	if err != nil {
		return {}, err
	}

	accept := new(NFA_State)
	accept^ = NFA_Accept{}
	link(final_frag.ends[:], accept)

	return {final_frag.first_state}, nil
}

destroy_nfa :: proc(nfa: ^NFA_State) {}

NFA_State :: union {
	NFA_Rune,
	NFA_Split,
	NFA_Begin_Capture,
	NFA_End_Capture,
	NFA_Accept,
}

NFA_Rune :: struct {
	matches: Rune_Matcher,
	next: ^NFA_State,
}

NFA_Split :: struct {
	options: [2]^NFA_State
}

NFA_Begin_Capture :: struct {
	group: int,
	next: ^NFA_State,
}

NFA_End_Capture :: struct {
	next: ^NFA_State,
}

NFA_Accept :: struct{}

Rune_Matcher :: struct {
	runes: union #no_nil {
		rune,
		[]Rune_Range,
		Rune_Class,
	},
	invert: bool,
}

Rune_Range :: struct {
	start, end: rune,
}
Rune_Class :: enum {
	Any,
	Alpha,
	Number,
	Word,
	Space,
	Punctuation,
}
