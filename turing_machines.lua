-- Turing machines
--
-- Collection of turing machines
-- affecting different parameters
--

-- TODO Use note length instead of seconds for duration (e.g. 1, 1/2, 1/4, ...) (be careful about rounding when getting the value in play_next_note method)
-- TODO Add midi and output control (similar to awake)

-- TODO Add synth params control

-- TODO Refactor using class for sequences

mu = require "musicutil"
ui = require 'ui'
util = require 'util'
fm = require 'formatters'

turing_params = {"note", "velocity", "ratcheting", "duration", "probability"}
sequences = {}
positions = {}
paused = {}
dials = {}

engine.name = 'PolyPerc'

scale_notes = {}
running = true
current_page = 1
alt = false

ratcheting_options = {1, 2, 3, 4, 6, 8, 12, 16, 24}
durations_labels = {'1', '1/2', '1/4', '1/8', '1/16'}
durations_values = {1, 1/2, 1/4, 1/8, 1/16}
durations = {}
for i=1,#durations_labels do durations[durations_labels[i]] = durations_values end

ratcheting_metro = metro.init()

function init()
    for i=1,#turing_params do
        init_sequence(turing_params[i])
        positions[turing_params[i]] = 1
        dials[turing_params[i]] = {
            steps=ui.Dial.new(55, 28, 22, 8, 1, 16, 1, 1, {8}),
            knob=ui.Dial.new(100, 28, 22, 50, 0, 100, 1, 50, {50})
        }
        paused[turing_params[i]] = false
    end
    set_params()
    build_scale()

    screen.line_width(1)
    screen.aa(1)

    norns.enc.sens(1, 12)

    for i=1,#turing_params do
        dials[turing_params[i]].steps:set_value(params:get(turing_params[i]..'_steps'))
        dials[turing_params[i]].knob:set_value(get_linexp_knob_value(params:get(turing_params[i]..'_knob')))
    end

    ratcheting_metro.event = play_next_note

    clock.run(update)
end

function set_params()
    params:add_separator("Common")

    params:add{type="trigger", id="start", name="Start", action=function() reset() start() end}
    params:add{type="trigger", id="stop", name="Stop", action=function() stop() end}

    params:add_separator("Machines")

    local cs_SEQL = controlspec.new(1,16,'lin',1,8,'')
    local cs_KNOB = controlspec.new(0,100,'lin',1,50,'%')

    params:add_group("Notes", 5)
    params:add_control("note_steps", "Steps", cs_SEQL)
    params:add_control("note_knob", "Knob", cs_KNOB)
    local cs_NOTE = controlspec.MIDINOTE:copy();
    cs_NOTE.default = 48;
    cs_NOTE.step = 1;
    params:add{type="control", id="root_note", name="Root", controlspec=cs_NOTE,
    formatter=function(param) return mu.note_num_to_name(param:get(), true) end, action=function(x) build_scale() end}
    params:add{type="number", id="scale", name="Scale", min=1, max=#mu.SCALES, default=1,
    formatter=function(param) return mu.SCALES[param:get()].name end, action=function(x) build_scale() end}
    local cs_OCTR = controlspec.new(1,4,'lin',1,2,'');
    params:add{type="control", id="octave_range", name="Octave range", controlspec=cs_OCTR, formatter=fm.round(1),
    action=function(x) build_scale() end}

    params:add_group("Velocity", 4)
    params:add_control("velocity_steps", "Steps", cs_SEQL)
    params:add_control("velocity_knob", "Knob", cs_KNOB)
    local cs_V = controlspec.MIDIVELOCITY:copy();
    cs_V.default = 30;
    params:add_control("velocity_min", "Min", cs_V, fm.round(1))
    cs_V = controlspec.MIDIVELOCITY:copy();
    cs_V.default = 100;
    params:add_control("velocity_max", "Max", cs_V, fm.round(1))

    params:add_group("Ratcheting", 4)
    params:add_control("ratcheting_steps", "Steps", cs_SEQL)
    params:add_control("ratcheting_knob", "Knob", cs_KNOB)
    params:add{type="option", id="ratcheting_min", name="Min", options=ratcheting_options, default=1} -- ratcheting_options[1]
    params:add{type="option", id="ratcheting_max", name="Max", options=ratcheting_options, default=4} -- ratcheting_options[4]

    params:add_group("Duration", 4)
    params:add_control("duration_steps", "Steps", cs_SEQL)
    params:add_control("duration_knob", "Knob", cs_KNOB)
    local cs_DUR = controlspec.new(1,#durations_labels,'lin',1,1)
    params:add{type="control", id="duration_min", name="Min", controlspec=cs_DUR, formatter=function(param) return durations_labels[param:get()] end}
    cs_DUR = cs_DUR:copy()
    cs_DUR.default = 3
    params:add{type="control", id="duration_max", name="Max", controlspec=cs_DUR, formatter=function(param) return durations_labels[param:get()] end}

    params:add_group("Probability", 4)
    params:add_control("probability_steps", "Steps", cs_SEQL)
    params:add_control("probability_knob", "Knob", cs_KNOB)
    local cs_PROB = controlspec.AMP
    cs_PROB.default = 0.75
    params:add_control("probability_min", "Min", cs_PROB)
    cs_PROB = controlspec.AMP
    cs_PROB.default = 1
    params:add_control("probability_max", "Max", cs_PROB)

    params:default()
end

function get_linexp_knob_value(x)
    x = x - 50
    if (x > 0) then
        x = util.linexp(0, 50, 1, 51, x) - 1
    else
        x = util.linexp(-50, 0, -51, -1, x) + 1
    end
    return util.round(x+50, 0.5)
end

function build_scale()
    scale_notes = mu.generate_scale(params:get("root_note"), params:get("scale"), params:get("octave_range"))
end

function init_sequence(param_name)
    sequences[param_name] = {}
    for i=1,16 do
        sequences[param_name][i] = math.random()
    end
end

function update_sequence(param_name)
    mutate_sequence(param_name)
    local current_value = sequences[param_name][positions[param_name]]
    if not paused[param_name] then move_to_next_position(param_name) end
    return current_value
end

function move_to_next_position(param_name)
    positions[param_name] = util.wrap(positions[param_name] + 1, 1, params:get(param_name..'_steps'))
end

function mutate_sequence(param_name)
    local k = params:get(param_name.."_knob")
    local cp = positions[param_name]
    if k < 50 then
        local p = 50 - k
        if math.random(50) <= p then sequences[param_name][cp] = math.random() end
    elseif k > 50 then
        local p = k - 50
        local sl = params:get(param_name..'_steps')
        if math.random(50) <= p then
            local other = cp
            while other == cp do other = math.random(sl) end
            local tmp = sequences[param_name][other]
            sequences[param_name][other] = sequences[param_name][cp]
            sequences[param_name][cp] = tmp
        end
    end
end

function update()
    while true do
        clock.sync(1)
        if running then
            local ratcheting = update_sequence("ratcheting")
            ratcheting = math.floor(ratcheting * math.abs(params:get("ratcheting_max") - params:get("ratcheting_min")) + math.min(params:get("ratcheting_max"), params:get("ratcheting_min")) + 0.5) -- + 0.5 to round instead of floor
            play_next_note()
            if ratcheting > 1 then
                ratcheting_metro:start(clock:get_beat_sec() / ratcheting, ratcheting-1)
            end
        end
    end
end

function play_next_note()
    local probability = update_sequence("probability")
    probability = probability * math.abs(params:get("probability_max") - params:get("probability_min")) + math.min(params:get("probability_max"), params:get("probability_min"))
    local should_play = math.random() <= probability

    local duration_index = update_sequence("duration")
    duration_index = math.floor(duration_index * math.abs(params:get("duration_max") - params:get("duration_min")) + math.min(params:get("duration_max"), params:get("duration_min")) + 0.5)
    local duration = durations_values[duration_index]
    if should_play then engine.release(clock:get_beat_sec() * duration) end

    local next = update_sequence("velocity")
    next = next * math.abs(params:get("velocity_max") - params:get("velocity_min")) + math.min(params:get("velocity_max"), params:get("velocity_min"))
    next = next / 127
    if should_play then engine.amp(next) end

    next = update_sequence("note")
    next = math.floor(next * params:get("octave_range") * 12 + params:get("root_note"))
    next = mu.snap_note_to_array(next, scale_notes)
    if should_play then engine.hz(mu.note_num_to_freq(next)) end

    redraw()
end

function start()
    running = true
end

function stop()
    running = false
end

function reset()
    for i=1,#turing_params do
        positions[turing_params[i]]=1
    end
end

function clock.transport.start()
    start()
end

function clock.transport.stop()
    stop()
end

function clock.transport.reset()
    reset()
end

function control_note_page(index, delta)
    if index==2 then
        params:delta('root_note', delta)
    elseif index==3 then
        params:delta('octave_range', delta)
    end
end

function control_velocity_page(index, delta)
    if index==2 then
        params:delta('velocity_min', delta)
    elseif index==3 then
        params:delta('velocity_max', delta)
    end
end

function control_ratcheting_page(index, delta)
    if index==2 then
        params:delta('ratcheting_min', delta)
    elseif index==3 then
        params:delta('ratcheting_max', delta)
    end
end

function control_duration_page(index, delta)
    if index==2 then
        params:delta('duration_min', delta)
    elseif index==3 then
        params:delta('duration_max', delta)
    end
end

function control_probability_page(index, delta)
    if index==2 then
        params:delta('probability_min', delta)
    elseif index==3 then
        params:delta('probability_max', delta)
    end
end

function enc(index, delta)
    if index==1 then
        current_page = util.clamp(current_page + delta, 1, #turing_params)
    end

    if not alt then
        if index==2 then
            params:delta(turing_params[current_page]..'_steps', delta)
            local v = params:get(turing_params[current_page]..'_steps')
            dials[turing_params[current_page]].steps:set_value(v)
            dials[turing_params[current_page]].steps:set_marker_position(1, v)
        elseif index==3 then
            params:delta(turing_params[current_page]..'_knob', delta)
            local v = get_linexp_knob_value(params:get(turing_params[current_page]..'_knob'))
            dials[turing_params[current_page]].knob:set_value(v)
            dials[turing_params[current_page]].knob:set_marker_position(1, v)
        end
    else
        if current_page == 1 then control_note_page(index, delta)
        elseif current_page == 2 then control_velocity_page(index, delta)
        elseif current_page == 3 then control_ratcheting_page(index, delta)
        elseif current_page == 4 then control_duration_page(index, delta)
        elseif current_page == 5 then control_probability_page(index, delta) end
    end

    redraw()
end

function key(index, state)
    local current_param = turing_params[current_page]
    if index == 1 then
        alt = state == 1
        dials[current_param].steps.active = not alt
        dials[current_param].knob.active = not alt
    elseif index == 2 and state == 1 then
        -- move to next step
        if alt then move_to_next_position(current_param)
            -- pause sequence
        else paused[current_param] = not paused[current_param] end
    elseif index == 3 and state == 1 then
        -- randomize current step
        if alt then sequences[current_param][positions[current_param]] = math.random()
            -- randomize whole sequence
        else init_sequence(current_param) end
    end
    redraw()
end

text_positions = {
    title=5,
    top_label=25,
    top_value=35,
    bottom_label=45,
    bottom_value=55
}
function draw_note_page()
    screen.level(1)
    screen.move(0, text_positions.top_label)
    screen.text('Root note')
    screen.move(0, text_positions.bottom_label)
    screen.text('Octaves')
    if alt then screen.level(15) else screen.level(1) end
    screen.move(0, text_positions.top_value)
    screen.text(params:string('root_note'))
    screen.move(0, text_positions.bottom_value)
    screen.text(params:string('octave_range'))
end

function draw_velocity_page()
    screen.level(1)
    screen.move(0, text_positions.top_label)
    screen.text('Min')
    screen.move(0, text_positions.bottom_label)
    screen.text('Max')
    if alt then screen.level(15) else screen.level(1) end
    screen.move(0, text_positions.top_value)
    screen.text(params:string('velocity_min'))
    screen.move(0, text_positions.bottom_value)
    screen.text(params:string('velocity_max'))
end

function draw_ratcheting_page()
    screen.level(1)
    screen.move(0, text_positions.top_label)
    screen.text('Min')
    screen.move(0, text_positions.bottom_label)
    screen.text('Max')
    if alt then screen.level(15) else screen.level(1) end
    screen.move(0, text_positions.top_value)
    screen.text(params:string('ratcheting_min'))
    screen.move(0, text_positions.bottom_value)
    screen.text(params:string('ratcheting_max'))
end

function draw_duration_page()
    screen.level(1)
    screen.move(0, text_positions.top_label)
    screen.text('Min')
    screen.move(0, text_positions.bottom_label)
    screen.text('Max')
    if alt then screen.level(15) else screen.level(1) end
    screen.move(0, text_positions.top_value)
    screen.text(params:string('duration_min'))
    screen.move(0, text_positions.bottom_value)
    screen.text(params:string('duration_max'))
end

function draw_probability_page()
    screen.level(1)
    screen.move(0, text_positions.top_label)
    screen.text('Min')
    screen.move(0, text_positions.bottom_label)
    screen.text('Max')
    if alt then screen.level(15) else screen.level(1) end
    screen.move(0, text_positions.top_value)
    screen.text(params:string('probability_min'))
    screen.move(0, text_positions.bottom_value)
    screen.text(params:string('probability_max'))
end

function draw_seq()
    local current_param = turing_params[current_page]
    local s = sequences[current_param]
    local sl = params:get(current_param..'_steps')
    local start_index = positions[current_param]
    local index = start_index
    for i=0,math.min(sl - 1, 7) do
        index = util.wrap(start_index + i, 1, sl)
        screen.level(math.floor(s[index] * 15 + 1))
        screen.rect(60 + i * 8, text_positions.title - 5, 5, 5)
        screen.fill()
    end
end

function redraw()
    local current_param = turing_params[current_page]

    screen.clear()
    screen.fill()

    dials[current_param].steps:redraw()
    dials[current_param].knob:redraw()
    screen.move(53, 20)
    screen.text('Steps')
    screen.move(100, 20)
    screen.text('Knob')

    screen.level(1)
    screen.move(0, text_positions.title)
    screen.text(string.upper(current_param))

    if current_page == 1 then draw_note_page()
    elseif current_page == 2 then draw_velocity_page()
    elseif current_page == 3 then draw_ratcheting_page()
    elseif current_page == 4 then draw_duration_page()
    elseif current_page == 5 then draw_probability_page() end

    draw_seq()

    screen.update()
end
