-- Turing machines
--
-- Collection of turing machines
-- affecting different parameters
--

-- TODO
--
-- Add midi and output control (similar to awake) and settings to map each machine that makes sense to a midi cc
-- Remove require for already imported libraries (i.e. util, see here https://monome.org/docs/norns/reference/#system-globals)

mu = require "musicutil"
ui = require 'ui'
util = require 'util'
fm = require 'formatters'

Machine = include('lib/machine')

machines = {}
current_machine = nil

engine.name = 'TuringEngine'

scale_notes = {}
alt = false

engine_types={'Pulse', 'Sin', 'Saw', 'Tri'}
ratcheting_options = {1, 2, 3, 4, 6, 8, 12, 16, 24}
releases_labels = {'4', '2', '1', '1/2', '1/4', '1/8', '1/16'}
releases_values = {4, 2, 1, 1/2, 1/4, 1/8, 1/16}
releases = {}
for i=1,#releases_labels do releases[releases_labels[i]] = releases_values end

ratcheting_metro = metro.init()

function init()
    init_machines()
    set_params()
    build_scale()

    screen.line_width(1)
    screen.aa(1)

    norns.enc.sens(1, 12)

    ratcheting_metro.event = play_next_note
    clock.run(update)
end

function init_machines()
    local machine_ids = {"notes", "cutoff", "velocity", "ratcheting", "release", "probability", "pan"}
    local machine_labels = {"Notes", "Cutoff", "Velocity", "Ratcheting", "Release", "Probability", "Pan"}
    local previous = nil
    local machine = nil
    for i=1,#machine_ids do
        machine = Machine.new(machine_ids[i], machine_labels[i])
        if previous then
            previous.next = machine
            machine.previous = previous
        end
        previous = machine
        machines[machine_ids[i]] = machine
        machine:add_hidden_params()
        machine:init_sequence()
    end

    current_machine = machines['notes']
end

function set_params()
    params:add_separator("Common")

    params:add{type="binary", id="running", name="Running", default=1, behavior='toggle',
        action=function(x) if x == 1 then reset() end end}

    params:add_group('Synth', 3)
    local cs = controlspec.new(1,#engine_types,'lin',1,1,'')
    params:add{type="control", id="type", name="Type", controlspec=cs,
        formatter=function(param) return engine_types[param:get()] end,
        action=function(x) engine.type(x) end}
    cs = controlspec.new(1,#releases_labels,'lin',1,4,'')
    params:add{type="control", id="attack", name="Attack", controlspec=cs,
        formatter=function(param) return releases_labels[param:get()] end,
        action=function(x) engine.attack(releases_values[x]) end}
    cs = controlspec.new(0,1,'lin',0.05,0.5,'')
    params:add{type="control", id="pw", name="Pulse width", controlspec=cs, action=function(x) engine.pw(x) end}

    params:add_separator("Machines")

    local cs_SEQL = controlspec.new(1,16,'lin',1,8,'')
    local cs_KNOB = controlspec.new(0,100,'lin',1,50,'%')
    local cs_CLKDIV = controlspec.new(1,16,'lin',1,1)

    -- Notes
    local machine = machines['notes']
    params:add_group(machine.label, 10)
    local cs_NOTE = controlspec.MIDINOTE:copy()
    cs_NOTE.default = 48
    cs_NOTE.step = 1
    machine:add_params(cs_SEQL, cs_KNOB, cs_CLKDIV, cs_NOTE, function(param) return mu.note_num_to_name(param:get(), true) end)
    params:add{type="control", id="root_note", name="Root note", controlspec=controlspec.new(0,11,'lin',1,0),
        formatter=function(param) return mu.note_num_to_name(param:get(), false) end, action=function(x) build_scale() end}
    params:add{type="number", id="scale", name="Scale", min=1, max=#mu.SCALES, default=1,
        formatter=function(param) return mu.SCALES[param:get()].name end, action=function() build_scale() end}
    local cs_OCT = controlspec.new(0,8,'lin',1,2,'')
    params:add{type="control", id="min_oct", name="Min octave", controlspec=cs_OCT, formatter=fm.round(1),
        action=function() build_scale() end}
    cs_OCT = cs_OCT:copy()
    cs_OCT.default = 3
    params:add{type="control", id="max_oct", name="Max octave", controlspec=cs_OCT, formatter=fm.round(1),
        action=function() build_scale() end}
    machine:set_extra_params({'min_oct', 'max_oct'}, {'Min oct.', 'Max oct.'})

    -- Cutoff
    machine = machines['cutoff']
    params:add_group(machine.label, 8)
    local cs_FREQ = controlspec.new(50,5000,'exp',10,1000,'Hz')
    machine:add_params(cs_SEQL, cs_KNOB, cs_CLKDIV, cs_FREQ)
    cs_FREQ = cs_FREQ:copy()
    cs_FREQ.default = 400
    params:add_control("cutoff_min", "Min", cs_FREQ, fm.round(1))
    cs_FREQ = cs_FREQ:copy()
    cs_FREQ.default = 1600
    params:add_control("cutoff_max", "Max", cs_FREQ, fm.round(1))
    machine:set_extra_params({'cutoff_min', 'cutoff_max'}, {'Min', 'Max'})

    -- Velocity
    machine = machines['velocity']
    params:add_group(machine.label, 8)
    local cs_V = controlspec.MIDIVELOCITY:copy()
    cs_V.default = 64
    machine:add_params(cs_SEQL, cs_KNOB, cs_CLKDIV, cs_V)
    cs_V = controlspec.MIDIVELOCITY:copy()
    cs_V.default = 30
    params:add_control("velocity_min", "Min", cs_V, fm.round(1))
    cs_V = controlspec.MIDIVELOCITY:copy()
    cs_V.default = 100
    params:add_control("velocity_max", "Max", cs_V, fm.round(1))
    machine:set_extra_params({'velocity_min', 'velocity_max'}, {'Min', 'Max'})

    -- Ratcheting
    machine = machines['ratcheting']
    params:add_group(machine.label, 8)
    local cs_RAT = controlspec.new(1,#ratcheting_options,'lin',1,1)
    machine:add_params(cs_SEQL, cs_KNOB, cs_CLKDIV, cs_RAT)
    cs_RAT = cs_RAT:copy()
    params:add{type="control", id="ratcheting_min", name="Min", controlspec=cs_RAT, formatter=function(param) return ratcheting_options[param:get()] end}
    cs_RAT = cs_RAT:copy()
    cs_RAT.default = 4
    params:add{type="control", id="ratcheting_max", name="Max", controlspec=cs_RAT, formatter=function(param) return ratcheting_options[param:get()] end}
    machine:set_extra_params({'ratcheting_min', 'ratcheting_max'}, {'Min', 'Max'})

    -- Release
    machine = machines['release']
    params:add_group(machine.label, 8)
    local cs_DUR = controlspec.new(1,#releases_labels,'lin',1,3)
    machine:add_params(cs_SEQL, cs_KNOB, cs_CLKDIV, cs_DUR)
    cs_DUR = cs_DUR:copy()
    params:add{type="control", id="release_min", name="Min", controlspec=cs_DUR, formatter=function(param) return releases_labels[param:get()] end}
    cs_DUR = cs_DUR:copy()
    cs_DUR.default = 5
    params:add{type="control", id="release_max", name="Max", controlspec=cs_DUR, formatter=function(param) return releases_labels[param:get()] end}
    machine:set_extra_params({'release_min', 'release_max'}, {'Min', 'Max'})

    -- Probability
    machine = machines['probability']
    params:add_group(machine.label, 8)
    local cs_PROB = controlspec.AMP:copy()
    cs_PROB.default = 1
    machine:add_params(cs_SEQL, cs_KNOB, cs_CLKDIV, cs_PROB)
    cs_PROB = controlspec.AMP:copy()
    cs_PROB.default = 0.75
    params:add_control("probability_min", "Min", cs_PROB)
    cs_PROB = controlspec.AMP:copy()
    cs_PROB.default = 1
    params:add_control("probability_max", "Max", cs_PROB)
    machine:set_extra_params({'probability_min', 'probability_max'}, {'Min', 'Max'})

    -- Pan
    machine = machines['pan']
    params:add_group(machine.label, 8)
    local cs_PAN = controlspec.new(-1,1,'lin',0.1,0)
    machine:add_params(cs_SEQL, cs_KNOB, cs_CLKDIV, cs_PAN)
    cs_PAN = cs_PAN:copy()
    cs_PAN.default = -0.3
    params:add_control("pan_min", "Min", cs_PAN)
    cs_PAN = cs_PAN:copy()
    cs_PAN.default = 0.3
    params:add_control("pan_max", "Max", cs_PAN)
    machine:set_extra_params({'pan_min', 'pan_max'}, {'Min', 'Max'})

    params:default()
    -- Refresh dials of all machines to match default preset
    for _, machine in pairs(machines) do
        machine:refresh_dials_values(true, true)
    end
end

function build_scale()
    local min = math.min(params:get('min_oct'), params:get('max_oct')) + 1
    local max = math.max(params:get('min_oct'), params:get('max_oct')) + 1
    scale_notes = mu.generate_scale(params:get("root_note") + min * 12, params:get("scale"), max - min + 1)
    -- Remove last note
    scale_notes[#scale_notes] = nil
end

function round_value(value, min, max)
    return value * math.abs(max - min) + math.min(min, max)
end

function round_index(index, min, max)
    return math.floor(round_value(index, min, max) + 0.5)
end

function map_note(note, min_oct, max_oct)
    return  math.floor(round_value(note, (min_oct+1) * 12, (max_oct+2) * 12))
end

function update()
    while true do
        clock.sync(1)
        if params:get('running') == 1 then
            local ratcheting = ratcheting_options[machines['ratcheting']:get_next_value(round_index)]
            play_next_note()
            if ratcheting > 1 then
                ratcheting_metro:start(clock:get_beat_sec() / ratcheting, ratcheting-1)
            end
        end
    end
end

function play_next_note()
    local probability = machines['probability']:get_next_value(round_value)
    local should_play = math.random() <= probability

    local release = releases_values[machines['release']:get_next_value(round_index)]
    if should_play then engine.release(clock:get_beat_sec() * release) end

    local velocity = machines['velocity']:get_next_value(round_value) / 127
    if should_play then engine.amp(velocity) end

    local cutoff = machines['cutoff']:get_next_value(round_value)
    if should_play then engine.cutoff(cutoff) end

    local pan = machines['pan']:get_next_value(round_value)
    if should_play then engine.pan(pan) end

    local note = mu.snap_note_to_array(machines['notes']:get_next_value(map_note), scale_notes)
    if should_play then engine.hz(mu.note_num_to_freq(note)) end

    redraw()
end

function reset()
    for _, machine in pairs(machines) do
        machine.position = 1
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

function enc(index, delta)
    if index==1 then
        if delta < 0 and current_machine.previous then
            current_machine = current_machine.previous
        elseif delta > 0 and current_machine.next then
            current_machine = current_machine.next
        end
    end

    if current_machine:get_active() then
        if not alt then
            if index==2 then
                current_machine:set_steps_delta(delta)
            elseif index==3 then
                current_machine:set_knob_delta(delta)
            end
        else
            current_machine:extra_controls_delta(index, delta)
        end
    else
        current_machine:extra_controls_delta(index, delta)
    end

    redraw()
end

function key(index, state)
    if current_machine:get_active() then
        if index == 1 then
            alt = state == 1
            current_machine:set_dials_active(not alt)
        elseif index == 2 and state == 1 then
            if alt then current_machine:move_to_next_position()
            else current_machine:toggle_running() end
        elseif index == 3 and state == 1 then
            if alt then current_machine:randomize_current_step()
            else current_machine:init_sequence() end
        end
        redraw()
    end
end

function redraw()
    screen.clear()
    screen.fill()
    current_machine:redraw()
    screen.update()
end
