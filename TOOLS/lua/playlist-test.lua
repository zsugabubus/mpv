-- Usage: mpv --script=TOOLS/lua/playlist-test.lua --idle

local num_assertions = 0

local function abort()
    mp.commandv("quit", "1")
    return assert(false, "abort")
end

local function done()
    print(string.format("SUCCESS. %d assertions passed.", num_assertions))
    mp.commandv("quit")
end

local function assert_eq(left, right)
    local utils = require("mp.utils")

    local left_str = utils.to_string(left)
    local right_str = utils.to_string(right)

    if left_str == right_str then
        num_assertions = num_assertions + 1
        return
    end

    print(
        ("Assertion `left == right` failed\n left = %s\nright = %s"):format(
            left_str,
            right_str
        )
    )
    return abort()
end

local function assert(b)
    return assert_eq(b, true)
end

local function test(name, run)
    print(("test %s ..."):format(name))
    return run()
end

test("mp.utils to_string", function()
    local to_string = require("mp.utils").to_string

    assert_eq(to_string(nil), [[nil]])
    assert_eq(to_string(false), [[false]])
    assert_eq(to_string(true), [[true]])
    assert_eq(to_string(0), [[0]])
    assert_eq(to_string(-1), [[-1]])
    assert_eq(to_string(1.5), [[1.5]])
    assert_eq(to_string(""), [[""]])
    assert_eq(to_string("string"), [["string"]])
    assert_eq(to_string([["'\n]]), [["\"'\\n"]])
    assert_eq(to_string({}), [[{}]])
    assert_eq(to_string({ 0 }), [[{0}]])
    assert_eq(to_string({ 0, 1, 2 }), [[{0, 1, 2}]])
    assert_eq(to_string({ [0] = false, [1] = true }), [[{true, [0] = false}]])
    assert_eq(to_string({ [2] = 0, [3] = 0 }), [[{[2] = 0, [3] = 0}]])
    assert_eq(to_string({ 1, 2, [4] = 0 }), [[{1, 2, [4] = 0}]])
    assert_eq(
        to_string({ [-1] = "-", 1, [1.5] = "+", 2 }),
        [[{1, 2, [-1] = "-", [1.5] = "+"}]]
    )
    assert_eq(to_string({ [2] = 0, [10] = 0 }), [[{[2] = 0, [10] = 0}]])
    assert_eq(to_string({ a = "b" }), [[{a = "b"}]])
    assert_eq(
        to_string({ [false] = "f", [true] = "t" }),
        [[{[false] = "f", [true] = "t"}]]
    )
    assert_eq(
        to_string({ 1, 2, 3, [10] = "x", a = 0, b = 0, c = 0 }),
        [[{1, 2, 3, [10] = "x", a = 0, b = 0, c = 0}]]
    )
    assert_eq(to_string({ 1, { a = { 2 } } }), [[{1, {a = {2}}}]])
    assert_eq(string.find(to_string(function() end), "^function:"), 1)
    local x = { "b" }
    x.i = { [x] = x }
    assert_eq(to_string(x), [=[{"b", i = {[[cycle]] = [cycle]}}]=])
end)

test("playlist", function()
    local function get_playlist()
        return mp.get_property_native("playlist")
    end

    local function get_playlist_pos()
        return mp.get_property_native("playlist-pos")
    end

    local function set_playlist(v)
        return mp.set_property_native("playlist", v)
    end

    local function change_playlist(v)
        assert_eq({ set_playlist(v) }, { true })
        return get_playlist()
    end

    assert_eq(get_playlist(), {})

    assert_eq({ set_playlist() }, { nil, "unsupported format for accessing property" })

    assert_eq(change_playlist({ {}, {} }), {})
    assert_eq(change_playlist({ -1, 0, 1 }), {})
    assert_eq(change_playlist({ { id = 0 }, { id = 1 } }), {})

    -- Create new entry from filename.
    assert_eq(change_playlist({ "." }), { { id = 1, filename = "." } })

    -- Retrieve existing entry by index and id.
    assert_eq(change_playlist({ 0 }), { { id = 1, filename = "." } })
    assert_eq(change_playlist({ { id = 1 } }), { { id = 1, filename = "." } })
    assert_eq(change_playlist({ 0, 0, { id = 1 } }), { { id = 1, filename = "." } })

    -- Cannot change filename.
    assert_eq(
        change_playlist({ { id = 1, filename = "ignored" } }),
        { { id = 1, filename = "." } }
    )

    -- Set and clear title.
    assert_eq(
        change_playlist({ { id = 1, title = "new title" } }),
        { { id = 1, filename = ".", title = "new title" } }
    )
    assert_eq(
        change_playlist({ { id = 1, title = "new title 2" } }),
        { { id = 1, filename = ".", title = "new title 2" } }
    )
    assert_eq(
        change_playlist({ { id = 1, title = "" } }),
        { { id = 1, filename = "." } }
    )

    local anull = "av://lavfi:anullsrc"

    -- Create new entry.
    assert_eq(
        change_playlist({ { filename = anull, title = "title", current = false } }),
        { { id = 2, filename = anull, title = "title" } }
    )

    print('------------------------')
    -- Create new entry and play.
    assert_eq(
        change_playlist({ { filename = anull, current = true } }),
        { { id = 3, filename = anull, current = true } }
    )

    print('Waiting for playback to start...')

    local entries_added_at

    mp.observe_property('time-pos', 'native', function(_, time_pos)
        time_pos = time_pos or -1
        print('time-pos', time_pos)

        if not entries_added_at then
            if time_pos <= 1 then
                return
            end

            entries_added_at = time_pos

            assert_eq(
                change_playlist({ anull, {id = 3}, anull, anull, anull}),
                {
                    { id = 4, filename = anull },
                    { id = 3, filename = anull, current = true, playing = true },
                    { id = 5, filename = anull },
                    { id = 6, filename = anull },
                    { id = 7, filename = anull },
                }
            )

            return
        end

        -- Playback not restarted.
        assert(time_pos > entries_added_at)

        assert_eq(
            change_playlist({ { id = 4 }, { id = 5 }, { id = 6 }, { id = 7 } }),
            {
                { id = 4, filename = anull },
                { id = 5, filename = anull, current = true },
                { id = 6, filename = anull },
                { id = 7, filename = anull },
            }
        )
        assert_eq(
            change_playlist({ { id = 4 }, { id = 7 } }),
            {
                { id = 4, filename = anull },
                { id = 7, filename = anull, current = true },
            }
        )
        assert_eq(
            change_playlist({ { id = 4 } }),
            {
                { id = 4, filename = anull },
            }
        )
        mp.commandv('playlist-clear')

        done()
    end)
end)
