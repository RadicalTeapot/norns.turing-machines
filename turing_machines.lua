-- Turing machines
--
-- Collection of turing machines
-- affecting different parameters
--

-- TODO
--
-- Fix issue with presets
-- (Also sequences are not saved in presets right now as they're not params, make them params (each step a param) and hide them using params:hide)
--
-- Change active and running trigger params to binary params so they can show their state and be saved in presets
--
-- Add pan machine
--
-- Add midi and output control (similar to awake) and settings to map each machine that makes sense to a midi cc
--
-- Copy TestEngine into lib folder and rename it to TuringEngine, add synth control params
--
-- Refactor: Add name of extra two params (ones displayed on pages) to machines so the control... and draw...
-- methods can be implemented there and simplify this file
--
-- Refactor: Rename duration to env or release

mu = require "musicutil"
ui = require 'ui'
util = require 'util'
fm = require 'formatters'

Machine = include('lib/machine')

machines = {}
current_machine = nil

engine.name = 'TestEngine'

scale_notes = {}
running = true
alt = false

ratcheting_options = {1, 2, 3, 4, 6, 8, 12, 16, 24}
durations_labels = {'1', '1/2', '1/4', '1/8', '1/16'}
durations_values = {1, 1/2, 1/4, 1/8, 1/16}
durations = {}
for i=1,#durations_labels do durations[durations_labels[i]] = durations_values end

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
    local machine_ids = {"notes", "cutoff", "velocity", "ratcheting", "duration", "probability"}
    local machine_labels = {"Notes", "Cutoff", "Velocity", "Ratcheting", "Duration", "Probability"}
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
    end

    current_machine = machines['notes']
end

function set_params()
    params:add_separator("Common")

    params:add{type="trigger", id="start", name="Start", action=function() reset() start() end}
    params:add{type="trigger", id="stop", name="Stop", action=function() stop() end}

    params:add_separator("Machines")

    local cs_SEQL = controlspec.new(1,16,'lin',1,8,'')
    local cs_KNOB = controlspec.new(0,100,'lin',1,50,'%')
    local cs_CLKDIV = controlspec.new(1,16,'lin',1,1)

    -- Notes
    local machine = machines['notes']
    params:add_group(machine.label, 9)
    local cs_NOTE = controlspec.MIDINOTE:copy()
    cs_NOTE.default = 48
    cs_NOTE.step = 1
    machine:add_params(cs_SEQL, cs_KNOB, cs_NOTE, cs_CLKDIV)
    params:add{type="control", id="root_note", name="Root", controlspec=cs_NOTE,
    formatter=function(param) return mu.note_num_to_name(param:get(), true) end, action=function(x) build_scale() end}
    params:add{type="number", id="scale", name="Scale", min=1, max=#mu.SCALES, default=1,
    formatter=function(param) return mu.SCALES[param:get()].name end, action=function(x) build_scale() end}
    local cs_OCTR = controlspec.new(1,4,'lin',1,2,'')
    params:add{type="control", id="octave_range", name="Octave range", controlspec=cs_OCTR, formatter=fm.round(1),
    action=function(x) build_scale() end}

    -- Cutoff
    machine = machines['cutoff']
    params:add_group(machine.label, 8)
    local cs_FREQ = controlspec.new(50,5000,'exp',10,1000,'Hz')
    machine:add_params(cs_SEQL, cs_KNOB, cs_FREQ, cs_CLKDIV)
    cs_FREQ = cs_FREQ:copy()
    cs_FREQ.default = 400
    params:add_control("cutoff_min", "Min", cs_FREQ, fm.round(1))
    cs_FREQ = cs_FREQ:copy()
    cs_FREQ.default = 1600
    params:add_control("cutoff_max", "Max", cs_FREQ, fm.round(1))

    -- Velocity
    machine = machines['velocity']
    params:add_group(machine.label, 8)
    local cs_V = controlspec.MIDIVELOCITY:copy()
    cs_V.default = 64
    machine:add_params(cs_SEQL, cs_KNOB, cs_V, cs_CLKDIV)
    cs_V = controlspec.MIDIVELOCITY:copy()
    cs_V.default = 30
    params:add_control("velocity_min", "Min", cs_V, fm.round(1))
    cs_V = controlspec.MIDIVELOCITY:copy()
    cs_V.default = 100
    params:add_control("velocity_max", "Max", cs_V, fm.round(1))

    -- Ratcheting
    machine = machines['ratcheting']
    params:add_group(machine.label, 8)
    local cs_RAT = controlspec.new(1,#ratcheting_options,'lin',1,1)
    machine:add_params(cs_SEQL, cs_KNOB, cs_RAT, cs_CLKDIV)
    cs_RAT = cs_RAT:copy()
    params:add{type="control", id="ratcheting_min", name="Min", controlspec=cs_RAT, formatter=function(param) return ratcheting_options[param:get()] end}
    cs_RAT = cs_RAT:copy()
    cs_RAT.default = 4
    params:add{type="control", id="ratcheting_max", name="Max", controlspec=cs_RAT, formatter=function(param) return ratcheting_options[param:get()] end}

    -- Duration
    machine = machines['duration']
    params:add_group(machine.label, 8)
    local cs_DUR = controlspec.new(1,#durations_labels,'lin',1,1)
    machine:add_params(cs_SEQL, cs_KNOB, cs_DUR, cs_CLKDIV)
    cs_DUR = cs_DUR:copy()
    params:add{type="control", id="duration_min", name="Min", controlspec=cs_DUR, formatter=function(param) return durations_labels[param:get()] end}
    cs_DUR = cs_DUR:copy()
    cs_DUR.default = 3
    params:add{type="control", id="duration_max", name="Max", controlspec=cs_DUR, formatter=function(param) return durations_labels[param:get()] end}

    -- Probability
    machine = machines['probability']
    params:add_group(machine.label, 8)
    local cs_PROB = controlspec.AMP:copy()
    cs_PROB.default = 1
    machine:add_params(cs_SEQL, cs_KNOB, cs_PROB, cs_CLKDIV)
    cs_PROB = controlspec.AMP:copy()
    cs_PROB.default = 0.75
    params:add_control("probability_min", "Min", cs_PROB)
    cs_PROB = controlspec.AMP:copy()
    cs_PROB.default = 1
    params:add_control("probability_max", "Max", cs_PROB)

    params:default()
    -- Refresh dials of all machines to match default preset
    for _, machine in pairs(machines) do
        machine:refresh_dials_values(true, true)
    end
end

function build_scale()
    scale_notes = mu.generate_scale(
        params:get("root_note"), params:get("scale"), params:get("octave_range"))
end

function update()
    while true do
        clock.sync(1)
        if running then
            local machine = machines['ratcheting']
            local ratcheting_index
            if machine.active then
                ratcheting_index = machine:update_sequence_and_get_value()
                ratcheting_index = math.floor(ratcheting_index * math.abs(params:get("ratcheting_max") - params:get("ratcheting_min")) + math.min(params:get("ratcheting_max"), params:get("ratcheting_min")) + 0.5) -- + 0.5 to round instead of floor
            else
                ratcheting_index = machine:get_default()
            end
            local ratcheting = ratcheting_options[ratcheting_index]
            play_next_note()
            if ratcheting > 1 then
                ratcheting_metro:start(clock:get_beat_sec() / ratcheting, ratcheting-1)
            end
        end
    end
end

function play_next_note()
    local machine = machines['probability']
    local probability
    if machine.active then
        probability = machine:update_sequence_and_get_value()
        probability = probability * math.abs(params:get("probability_max") - params:get("probability_min")) + math.min(params:get("probability_max"), params:get("probability_min"))
    else
        probability = machine:get_default()
    end
    local should_play = math.random() <= probability

    machine = machines['duration']
    local duration_index
    if machine.active then
        duration_index = machine:update_sequence_and_get_value()
        duration_index = math.floor(duration_index * math.abs(params:get("duration_max") - params:get("duration_min")) + math.min(params:get("duration_max"), params:get("duration_min")) + 0.5)
    else
        duration_index = machine:get_default()
    end
    local duration = durations_values[duration_index]
    if should_play then
        engine.attack(clock:get_beat_sec() * duration * 0.1)
        engine.release(clock:get_beat_sec() * duration * 0.9)
    end

    machine = machines['velocity']
    local velocity
    if machine.active then
        velocity = machine:update_sequence_and_get_value()
        velocity = velocity * math.abs(params:get("velocity_max") - params:get("velocity_min")) + math.min(params:get("velocity_max"), params:get("velocity_min"))
        velocity = velocity / 127
    else
        velocity = machine:get_default()
    end
    if should_play then engine.amp(velocity) end

    machine = machines['cutoff']
    local cutoff
    if machine.active then
        cutoff = machine:update_sequence_and_get_value()
        cutoff = cutoff * math.abs(params:get("cutoff_max") - params:get("cutoff_min")) + math.min(params:get("cutoff_max"), params:get("cutoff_min"))
    else
        cutoff = machine:get_default()
    end
    if should_play then engine.cutoff(cutoff) end

    machine = machines['notes']
    local note
    if machine.active then
        note = machine:update_sequence_and_get_value()
        note = math.floor(note * params:get("octave_range") * 12 + params:get("root_note"))
        note = mu.snap_note_to_array(note, scale_notes)
    else
        note = machine:get_default()
    end
    if should_play then engine.hz(mu.note_num_to_freq(note)) end

    redraw()
end

function start()
    running = true
end

function stop()
    running = false
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

function control_note_page(index, delta)
    if index==2 then
        params:delta('root_note', delta)
    elseif index==3 then
        params:delta('octave_range', delta)
    end
end

function control_cutoff_page(index, delta)
    if index==2 then
        params:delta('cutoff_min', delta)
    elseif index==3 then
        params:delta('cutoff_max', delta)
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
        if delta < 0 and current_machine.previous then
            current_machine = current_machine.previous
        elseif delta > 0 and current_machine.next then
            current_machine = current_machine.next
        end
    end

    if current_machine.active then
        if not alt then
            if index==2 then
                current_machine:set_steps_delta(delta)
            elseif index==3 then
                current_machine:set_knob_delta(delta)
            end
        else
            if current_machine.id == 'notes' then control_note_page(index, delta)
            elseif current_machine.id == 'cutoff' then control_cutoff_page(index, delta)
            elseif current_machine.id == 'velocity' then control_velocity_page(index, delta)
            elseif current_machine.id == 'ratcheting' then control_ratcheting_page(index, delta)
            elseif current_machine.id == 'duration' then control_duration_page(index, delta)
            elseif current_machine.id == 'probability' then control_probability_page(index, delta) end
        end
    end

    redraw()
end

function key(index, state)
    if current_machine.active then
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

function draw_cutoff_page()
    screen.level(1)
    screen.move(0, text_positions.top_label)
    screen.text('Min')
    screen.move(0, text_positions.bottom_label)
    screen.text('Max')
    if alt then screen.level(15) else screen.level(1) end
    screen.move(0, text_positions.top_value)
    screen.text(params:string('cutoff_min'))
    screen.move(0, text_positions.bottom_value)
    screen.text(params:string('cutoff_max'))
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

function redraw()
    screen.clear()
    screen.fill()

    current_machine:draw_dials()

    screen.level(1)
    screen.move(0, text_positions.title)
    screen.text(string.upper(current_machine.label))

    if current_machine.id == 'notes' then draw_note_page()
    elseif current_machine.id == 'cutoff' then draw_cutoff_page()
    elseif current_machine.id == 'velocity' then draw_velocity_page()
    elseif current_machine.id == 'ratcheting' then draw_ratcheting_page()
    elseif current_machine.id == 'duration' then draw_duration_page()
    elseif current_machine.id == 'probability' then draw_probability_page() end

    current_machine:draw_sequence(60, text_positions.title, 5)

    screen.update()
end
