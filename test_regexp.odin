package regexp

import "core:testing"
import "core:fmt"


@test
test_basic :: proc(t: ^testing.T) {
	simple, err := compile("as?d+f*.")
	testing.expect(t, err == nil, "regex failed to compile")

	// fmt.println(simple)

	test_cases :=  []struct {
		s: string,
		is_match: bool,
	} {
		{ "asdf0", true },
		{ "adf0", true },
		{ "addddddddff0", true },
		{ "addddf", true },
		{ "af", false },
		{ "sdf", false },
	}

	for tcase in test_cases {
		match, err := match(simple, tcase.s)
		testing.expect_value(t, match != nil, tcase.is_match)
	}
}
