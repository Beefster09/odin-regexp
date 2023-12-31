package regexp

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:unicode"

Match :: struct {
	full: string,
	groups: []string,
}


match :: proc(p: Pattern, s: string, allocator := context.temp_allocator) -> (result: Maybe(Match), all_err: Error) {
	cur_ss := make([dynamic]Matcher_State, allocator)
	next_ss := make([dynamic]Matcher_State, allocator)

	append(&cur_ss, Matcher_State{
		state = p.initial_state,
		start = 0,
	})

	step :: proc(ms: Matcher_State, r: rune, i: int, next_ss: ^[dynamic]Matcher_State) {
		switch state in ms.state {
			case NFA_Accept:
				append(next_ss, ms)
			case NFA_Rune:
				if rune_in(r, state.matches) {
					next := ms
					next.state = state.next
					next.end = auto_cast i + 1
					if !slice.contains(next_ss[:], next) {
						append(next_ss, next)
					}
				}
			case NFA_Split:
				for next in state.options {
					sub := ms
					sub.state = next
					step(sub, r, i, next_ss)
				}
			case NFA_Begin_Capture:
				panic("not implemented")
			case NFA_End_Capture:
				panic("not implemented")
		}
	}

	for r, i in s {
		// fmt.println(r, cur_ss)
		for ms in cur_ss {
			step(ms, r, i, &next_ss)
		}
		cur_ss, next_ss = next_ss, cur_ss
		clear(&next_ss)

		if len(cur_ss) == 0 {
			return nil, nil
		}
	}

	is_accept :: proc(state: ^NFA_State) -> bool {
		#partial switch st in state {
			case NFA_Accept: return true
			case NFA_Split: return is_accept(st.options[0]) || is_accept(st.options[1])
		}
		return false
	}

	// fmt.printf("\"%s\" %#v\n", s, cur_ss)
	for ms in cur_ss {
		if is_accept(ms.state) {
			return Match{
				full = s[ms.start:ms.end],
			}, nil
		}
	}

	return nil, nil
}


Matcher_State :: struct {
	state: ^NFA_State,
	start, end: i32,
	// captures: []struct{},
}

rune_in :: proc(r: rune, matcher: Rune_Matcher) -> bool {
	switch m in matcher.runes {
		case rune:
			return (r == m) != matcher.invert
		case Rune_Class:
			switch m {
				case .Any: return !matcher.invert
				case .Alpha: return unicode.is_alpha(r) != matcher.invert
				case .Number: return unicode.is_number(r) != matcher.invert
				case .Punctuation: return unicode.is_punct(r) != matcher.invert
				case .Space: return unicode.is_space(r) != matcher.invert
				case .Word: return (r == '_' || unicode.is_alpha(r) || unicode.is_number(r)) != matcher.invert
			}
		case []Rune_Range:
			panic("not implemented")
	}
	return false
}
