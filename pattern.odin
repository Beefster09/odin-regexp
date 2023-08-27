package regexp

import sa "core:container/small_array"
import "core:strings"
import "core:runtime"
import "core:intrinsics"

Pattern :: struct {
	initial_state: ^NFA_State,
}

Error :: union {
	Regexp_Error,
	runtime.Allocator_Error,
}

Regexp_Error :: enum {
	ASDF,
}

compile :: proc(expr: string, allocator := context.allocator) -> (pattern: Pattern, err_all: Error) {
	Fragment :: struct {
		first_state: ^NFA_State,
		end_states: []^NFA_State,  // a list of all the unlinked states in the fragment (i.e. state.next == nil)
	}

	D :: struct {
		fragments: sa.Small_Array(100, Fragment),
		dangling_ends_pool: sa.Small_Array(200, ^NFA_State),
	}
	d: D

	defer if err_all != nil {
		for fragment in sa.slice(&d.fragments) {
			destroy_nfa(fragment.first_state)
		}
	}

	context.user_ptr = &d
	context.allocator = allocator

	push_state :: proc (state: NFA_State) -> ^Fragment {
		d := cast(^D) context.user_ptr

		state_ptr := new(NFA_State)
		state_ptr^ = state

		end_idx := sa.len(d.dangling_ends_pool)
		sa.push_back(&d.dangling_ends_pool, state_ptr)

		frag_idx := sa.len(d.fragments)
		sa.push_back(&d.fragments, Fragment{state_ptr, sa.slice(&d.dangling_ends_pool)[end_idx:]})
		return sa.get_ptr(&d.fragments, frag_idx)
	}

	push_empty :: proc () {
		d := cast(^D) context.user_ptr
		sa.push_back(&d.fragments, Fragment{nil, nil})
	}

	concat :: proc() {
		d := cast(^D) context.user_ptr

		f2 := sa.pop_back(&d.fragments)
		f1 := sa.pop_back(&d.fragments)

		if f1.first_state == nil {
			sa.push_back(&d.fragments, f2)
		} else {
			for end_ptr in f1.end_states {
				switch end_state in end_ptr {
					case NFA_Rune:
						end_state.next = f2.first_state
						end_ptr^ = end_state
					case NFA_Begin_Capture:
						end_state.next = f2.first_state
						end_ptr^ = end_state
					case NFA_End_Capture:
						end_state.next = f2.first_state
						end_ptr^ = end_state
					case NFA_Split:
						end_state.options[1] = f2.first_state
						end_ptr^ = end_state
					case NFA_Accept:
						panic("unreachable code")
				}
			}
			// remove the ends that we linked and update the fragment
			num_ends := sa.len(d.dangling_ends_pool)
			trim_idx := num_ends - (len(f1.end_states) + len(f2.end_states))
			new_ends := sa.slice(&d.dangling_ends_pool)[trim_idx:trim_idx + len(f2.end_states)]
			copy_slice(new_ends, f2.end_states)
			sa.push_back(&d.fragments, Fragment{f1, new_ends})
		}
	}

	push_empty()

	skip := 0
	for r, i in expr {
		if skip > 0 {
			skip -= 1
			continue
		}

		switch r {
			case '(':
			case '|':
				frag := sa.pop_back(&d.fragments)
				push_empty()
			case '?':
			case '*':
			case '+':
			case '[':
			case '\\':
			case '.':
				push_state(NFA_Rune{matches = { rule = Rune_Class.Any }})
				concat()
			case: // literal character
				push_state(NFA_Rune{matches = { rule = r }})
				concat()
		}
	}

	push_state(NFA_Accept{})
	concat()

	return pattern, nil
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
	rule: union {
		rune,
		Rune_Range,
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
