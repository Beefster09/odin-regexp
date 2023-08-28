package regexp

import "core:testing"
import "core:fmt"
import "core:runtime"


@test
test_basic :: proc(t: ^testing.T) {
	simple, err := compile("as?d+f*.")
	testing.expect(t, err == nil, "regex failed to compile")

	test_cases :=  []struct {
		loc: runtime.Source_Code_Location,
		s: string,
		is_match: bool,
	} {
		{ #location(), "asdf0", true },
		{ #location(), "adf0", true },
		{ #location(), "addddddddff0", true },
		{ #location(), "addddf", true },
		{ #location(), "addddf :)", true },  // beginning still matches
		{ #location(), "af", false },
		{ #location(), "sdf", false },
	}

	for tcase in test_cases {
		match, err := match(simple, tcase.s)
		testing.expect_value(t, match != nil, tcase.is_match)
	}
}

@test
test_escapes :: proc(t: ^testing.T) {
	escaped, err := compile(`\[\w+\s*\d+\]\s*\??`)
	testing.expect(t, err == nil, "regex failed to compile")

	test_cases := []struct {
		loc: runtime.Source_Code_Location,
		s: string,
		is_match: bool,
	} {
		{ #location(), "[foo 6]", true },
		{ #location(), "[bar42]?", true },
		{ #location(), "[baz69] \t  ?", true },
		{ #location(), "[_0]?", true },
		{ #location(), "[inkyblinkyandclyde    \t     \t     0]?", true },
		{ #location(), "[00]", true },
		{ #location(), "[0]", false },
		{ #location(), "inky 0]", false },
	}

	for tcase in test_cases {
		match, err := match(escaped, tcase.s)
		testing.expect_value(t, match != nil, tcase.is_match, tcase.loc)
	}
}
