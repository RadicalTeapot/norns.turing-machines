ui = require 'ui'

local Machine = {}
Machine.__index = Machine

function Machine.new(id, label, sequence_length, running, active)
    local s = setmetatable({}, Machine)
    s.id = id or 'machine'
    s.label = label or id or 'Machine'

    -- Length of the sequence
    s.sequence_length = sequence_length or 16
    -- Current step position in sequence array
    s.position = 1
    -- Whether this machine is running or froze on current step
    s.running = running or true
    -- Whether this machine is active or its default value is used
    s.active = active or true
    -- Link to previous machine in machines list
    s.previous = nil
    -- Link to next machine in machines list
    s.next = nil
    s.clock_count = 1

    s.dials = {
        steps=ui.Dial.new(55, 28, 22, 8, 1, s.sequence_length, 1, 1, {s.sequence_length * 0.5}),
        knob=ui.Dial.new(100, 28, 22, 50, 0, 100, 1, 50, {50})
    }

    return s
end

function Machine:add_params(sequence_controlspec, knob_controlspec, default_value_controlspec, clock_div_controlspec)
    params:add{type="trigger", id=self.id.."_active", name="Active", action=function() self:toggle_active() end}
    params:add_control(self.id.."_steps", "Steps", sequence_controlspec)
    params:add_control(self.id.."_knob", "Knob", knob_controlspec)
    params:add{type="trigger", id=self.id.."_running", name="Running", action=function() self:toggle_running() end}
    params:add_control(self.id..'_default', "Default", default_value_controlspec)
    params:add_control(self.id..'_clock_div', "Clock div", clock_div_controlspec)

    self.dials.steps:set_value(sequence_controlspec.default)
    self.dials.knob:set_value(get_linexp_value(knob_controlspec.default))
end

function Machine:add_hidden_params()
    local id
    for i=0,self.sequence_length do
        id = self.id..'_'..i
        params:add_number(id, '', 0, 1, 0)
        params:hide(id)
    end
end

function Machine:get_steps()
    return params:get(self.id..'_steps')
end

function Machine:set_steps_delta(delta)
    params:delta(self.id..'_steps', delta)
    self:refresh_dials_values(true, false)
end

function Machine:get_knob()
    return get_linexp_value(params:get(self.id..'_knob'))
end

function Machine:set_knob_delta(delta)
    params:delta(self.id..'_knob', delta)
    self:refresh_dials_values(false, true)
end

function Machine:refresh_dials_values(refresh_steps, refresh_knob)
    if refresh_steps then
        local new_value = params:get(self.id..'_steps')
        self.dials.steps:set_value(new_value)
        self.dials.steps:set_marker_position(1, new_value)
    end

    if refresh_knob then
        local new_value = get_linexp_value(params:get(self.id..'_knob'))
        self.dials.knob:set_value(new_value)
        self.dials.knob:set_marker_position(1, new_value)
    end
end

function Machine:get_default()
    return params:get(self.id..'_default')
end

function Machine:toggle_running()
    self.running = not self.running
end

function Machine:toggle_active()
    self.active = not self.active
    self:set_dials_active(self.active)
end

function Machine:step_name(step)
    return self.id..'_'..step
end

function Machine:init_sequence()
    for i=1,self.sequence_length do
        params:set(self:step_name(i), math.random())
    end
end

function Machine:randomize_current_step()
    params:set(self:step_name(self.position), math.random())
end

function Machine:current_value()
    return self:value_at(self.position)
end

function Machine:value_at(position)
    return params:get(self:step_name(position))
end

function Machine:update_sequence_and_get_value()
    self:mutate_sequence()
    local current_value = self:current_value()
    if self.running then
        if self.clock_count >= params:get(self.id..'_clock_div') then
            self:move_to_next_position()
            self.clock_count = 1
        else
            self.clock_count = self.clock_count + 1
        end
    end
    return current_value
end

function Machine:move_to_next_position()
    self.position = util.wrap(self.position + 1, 1, self:get_steps())
end

function Machine:mutate_sequence()
    local knob = self:get_knob()
    local steps = self:get_steps()
    if knob < 50 then
        local probability = 50 - knob
        if math.random(50) <= probability then
            self:randomize_current_step()
        end
    elseif knob > 50 then
        local probability = knob - 50
        if math.random(50) <= probability then
            -- Find other position to swap value with
            local other_position = self.position
            while other_position == self.position do
                other_position = math.random(steps)
            end

            -- Swap value with other position
            local tmp = self:value_at(other_position)
            params:set(self:step_name(other_position), self:current_value())
            params:set(self:step_name(self.position), tmp)
        end
    end
end

function Machine:draw_sequence(x, y, scale)
    local index = self.position
    local steps = self:get_steps()
    local max_level = 15
    if not self.active then max_level = 7 end
    for i=0,math.min(steps - 1, 7) do
        index = util.wrap(self.position + i, 1, steps)
        screen.level(math.floor(self:value_at(index) * max_level + 1))
        screen.rect(x + i * 8, y - scale, scale, scale)
        screen.fill()
    end
end

function Machine:draw_dials()
    self.dials.steps:redraw()
    self.dials.knob:redraw()
    screen.move(53, 20)
    screen.text('Steps')
    screen.move(100, 20)
    screen.text('Knob')
end

function Machine:set_dials_active(state)
    self.dials.steps.active = state
    self.dials.knob.active = state
end

function get_linexp_value(x)
    x = x - 50
    if (x > 0) then
        x = util.linexp(0, 50, 1, 51, x) - 1
    else
        x = util.linexp(-50, 0, -51, -1, x) + 1
    end
    return util.round(x+50, 0.5)
end

return Machine
