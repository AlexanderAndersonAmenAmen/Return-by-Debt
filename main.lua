--- STEAMODDED HEADER
--- MOD_NAME: Return by Debt
--- MOD_ID: ReturnByDebt
--- MOD_AUTHOR: [ReturnByDebt]
--- MOD_DESCRIPTION: Rewinds losing hands to an earlier Ante, to the run start, or to a new run.
--- PREFIX: rbd
--- VERSION: 1.4.3
----------------------------------------------

SMODS.Sound { key = 'rewind', path = 'rewind.ogg' }
SMODS.Sound { key = 'rewind_alt_1', path = 'rewind_alt_1.ogg' }
SMODS.Sound { key = 'rewind_alt_2', path = 'rewind_alt_2.ogg' }

ReturnByDebt = ReturnByDebt or {}
local R = ReturnByDebt

R.freeze_seconds = 0.4
R.jiggle_seconds = 0.3
R.reveal_seconds = 0.4
R.transition_seconds = R.freeze_seconds + R.reveal_seconds
R.sfx_seconds = 2.716735
R.fade_seconds = 2.0
R.phase = nil
R.sound_started = nil
R.rewind_started = nil
R.origin = nil
R.checkpoint = nil
R.scoring_now = false
R.last_hands_before = nil
R.music_scale = 1
R.first_card = nil
R.jiggle_started = nil
R.visual_phase = nil
R.visual_started = nil
R.frozen_image = nil
R.capture_image_data = nil
R.capture_requested = false
R.capture_requested_at = nil
R.capture_failed = false
R.capture_generation = 0
R.freeze_started = nil
R.restored = false
R.jiggle_draws = 0
R.score_event_index = nil
R.chips_event_index = nil
R.chips_feedback_at = nil
R.chips_feedback_draws = 0
R.blackout_alpha = 0
R.rescue_checks = R.rescue_checks or {}
R.history = R.history or nil
R.internal_start = false

local sfx_variants = {
    {key = 'rbd_rewind', duration = 2.716740},
    {key = 'rbd_rewind_alt_1', duration = 9.534694},
    {key = 'rbd_rewind_alt_2', duration = 7.536000},
}

local sfx_rng
if love and love.math and love.math.newRandomGenerator then
    local seed = os.time() + math.floor((love.timer and love.timer.getTime() or 0) * 1000000)
    sfx_rng = love.math.newRandomGenerator(seed)
end

function R.pick_sfx()
    local roll = sfx_rng and sfx_rng:random() or math.random()
    if roll < 0.5 then return sfx_variants[2] end
    if roll < 0.75 then return sfx_variants[2] end
    return sfx_variants[2]
end

local mod = SMODS.current_mod
local cfg = mod and mod.config or {redo = false, restart = true, remake = false, antes_back = 0}
R.config = cfg

local function clamp_antes(value)
    return math.max(0, math.min(4, math.floor((tonumber(value) or 0) + 0.5)))
end

function R.current_mode()
    if cfg.redo then return 'redo' end
    if cfg.remake then return 'remake' end
    return 'restart'
end

local function select_mode(which)
    cfg.redo = which == 'redo'
    cfg.restart = which == 'restart'
    cfg.remake = which == 'remake'
end

if G and G.FUNCS then
    G.FUNCS.rbd_select_redo = function() select_mode('redo') end
    G.FUNCS.rbd_select_restart = function() select_mode('restart') end
    G.FUNCS.rbd_select_remake = function() select_mode('remake') end
end

if not (cfg.redo or cfg.restart or cfg.remake) then select_mode('restart') end
if cfg.redo then select_mode('redo')
elseif cfg.remake then select_mode('remake')
else select_mode('restart') end
cfg.antes_back = clamp_antes(cfg.antes_back)

if mod then
    mod.config_tab = function()
        local U = G.UIT
        local pale = HEX('C8C8C8')
        local row_width = 7.5
        local text_offset = 0.65

        local function toggle_row(label, setting, callback)
            return {n = U.R, config = {align = 'cl', minw = row_width, padding = 0.02}, nodes = {
                {n = U.C, config = {align = 'cl', minw = 0.5, padding = 0.01}, nodes = {
                    create_toggle({col = true, label = '', ref_table = cfg, ref_value = setting, callback = callback, w = 0, scale = 0.8})
                }},
                {n = U.C, config = {align = 'cl', padding = 0.05}, nodes = {
                    {n = U.T, config = {text = label, scale = 0.55, colour = G.C.UI.TEXT_LIGHT}}
                }}
            }}
        end

        local function left_text_row(label, scale, colour)
            return {n = U.R, config = {align = 'cl', minw = row_width, padding = 0.02}, nodes = {
                {n = U.B, config = {w = text_offset, h = 0.01}},
                {n = U.C, config = {align = 'cl', padding = 0}, nodes = {
                    {n = U.T, config = {text = label, scale = scale, colour = colour}}
                }}
            }}
        end

        local function spacer_row()
            return {n = U.R, config = {align = 'cl', minw = row_width, padding = 0.1}, nodes = {}}
        end

        return {n = U.ROOT, config = {align = 'cl', padding = 0.15, r = 0.1, minw = row_width, colour = G.C.CLEAR}, nodes = {
            toggle_row('Re:do', 'redo', G.FUNCS.rbd_select_redo),
            left_text_row('Rewinds time by a certain amount of Antes', 0.4, G.C.UI.TEXT_LIGHT),
            left_text_row('setting to 0 rewinds the current Ante', 0.35, pale),
            left_text_row('Antes back', 0.4, G.C.UI.TEXT_LIGHT),
            {n = U.R, config = {align = 'cl', minw = row_width, padding = 0.03}, nodes = {
                {n = U.B, config = {w = text_offset, h = 0.01}},
                {n = U.C, config = {align = 'cl', padding = 0}, nodes = {
                    create_slider({label = '', w = 4.2, h = 0.35, ref_table = cfg, ref_value = 'antes_back', min = 0, max = 4, decimal_places = 0, label_scale = 0.4})
                }}
            }},
            spacer_row(),
            toggle_row('Re:start', 'restart', G.FUNCS.rbd_select_restart),
            left_text_row('Rewinds time to the start of the Run', 0.4, G.C.UI.TEXT_LIGHT),
            spacer_row(),
            toggle_row('Re:make', 'remake', G.FUNCS.rbd_select_remake),
            left_text_row('Starts a new run', 0.4, G.C.UI.TEXT_LIGHT)
        }}
    end
end

local function clone_tree(value, visited)
    if type(value) ~= 'table' then return value end
    visited = visited or {}
    if visited[value] then return visited[value] end
    local result = {}
    visited[value] = result
    for k, v in pairs(value) do result[clone_tree(k, visited)] = clone_tree(v, visited) end
    return result
end

local function clone_save(value)
    if type(STR_PACK) == 'function' and type(STR_UNPACK) == 'function' then
        local ok, result = pcall(function() return STR_UNPACK(STR_PACK(value)) end)
        if ok and type(result) == 'table' then return result end
    end
    return clone_tree(value)
end

local function history_file()
    if not (G and G.SETTINGS and G.SETTINGS.profile) then return nil end
    return tostring(G.SETTINGS.profile)..'/rbd_checkpoints.jkr'
end

function R.write_history()
    local filename = history_file()
    if not filename or not R.history or not love.filesystem or not love.data or type(STR_PACK) ~= 'function' then return end
    pcall(function()
        love.filesystem.createDirectory(tostring(G.SETTINGS.profile))
        local text = STR_PACK(R.history)
        local compressed = love.data.compress('string', 'deflate', text, 1)
        love.filesystem.write(filename, compressed)
    end)
end

local function load_history(run_id)
    local filename = history_file()
    if not filename or not love.filesystem or not love.data or type(STR_UNPACK) ~= 'function' then return nil end
    local ok, history = pcall(function()
        local binary = love.filesystem.read(filename)
        if not binary then return nil end
        return STR_UNPACK(love.data.decompress('string', 'deflate', binary))
    end)
    if ok and type(history) == 'table' and history.run_id == run_id and type(history.checkpoints) == 'table' then
        return history
    end
end

local function forget_history()
    R.history = nil
    local filename = history_file()
    if filename and love.filesystem and love.filesystem.remove then pcall(love.filesystem.remove, filename) end
end

function R.record_ante_snapshot()
    if R.internal_start or not (G and G.GAME and G.GAME.rbd_run_id and G.ARGS and G.ARGS.save_run) then return end
    if G.STAGE ~= G.STAGES.RUN or G.STATE ~= G.STATES.BLIND_SELECT then return end
    local rr = G.GAME.round_resets
    local ante = rr and tonumber(rr.ante)
    if not ante or ante < 1 then return end
    if not R.history or R.history.run_id ~= G.GAME.rbd_run_id then
        R.history = {run_id = G.GAME.rbd_run_id, checkpoints = {}}
    end
    if R.history.checkpoints[ante] then return end
    local snapshot = clone_save(G.ARGS.save_run)
    if type(snapshot.GAME) ~= 'table' or not snapshot.BACK or not snapshot.BLIND then return end
    R.history.checkpoints[ante] = snapshot
    for prior in pairs(R.history.checkpoints) do
        if type(prior) ~= 'number' or prior < ante - 4 or prior > ante then R.history.checkpoints[prior] = nil end
    end
    R.write_history()
end

local old_save_run = save_run
if type(old_save_run) == 'function' then
    function save_run(...)
        local outcome = old_save_run(...)
        if not G.F_NO_SAVING then R.record_ante_snapshot() end
        return outcome
    end
end

function R.pick_checkpoint(ante, count)
    if not R.history or not R.history.checkpoints then return nil end
    local target = math.max(1, ante - count)
    if R.history.checkpoints[target] then return target end
    if count > 0 then
        for older = target - 1, math.max(1, ante - 4), -1 do
            if R.history.checkpoints[older] then return older end
        end
    end
    return nil
end

function R.register_rescue_check(fn)
    if type(fn) == 'function' then
        R.rescue_checks[#R.rescue_checks + 1] = fn
    end
end

local function compare_below(a, b)
    if a == nil or b == nil then return nil end
    local ok, below = pcall(function()
        if type(to_big) == 'function' then
            return to_big(a) < to_big(b)
        end
        return a < b
    end)
    return ok and below or nil
end

local function compare_at_least(a, b)
    local below = compare_below(a, b)
    if below == nil then return false end
    return not below
end

local function can_be_saved_by_bones(predicted)
    local jokers = G.jokers and G.jokers.cards or {}
    for _, joker in ipairs(jokers) do
        if not joker.debuff and joker.ability and joker.ability.name == 'Mr. Bones' then
            local ok, quarter = pcall(function()
                if type(to_big) == 'function' then
                    return to_big(G.GAME.blind.chips) * 0.25
                end
                return G.GAME.blind.chips * 0.25
            end)
            if not ok or compare_at_least(predicted, quarter) then return true end
        end
    end
    return false
end

function R.mark_first_card(card)
    if not R.scoring_now or R.first_card or not G or not G.E_MANAGER then return end
    local queue = G.E_MANAGER.queues and G.E_MANAGER.queues.base
    if queue then
        R.checkpoint = #queue
        R.first_card = card
    end
end

local function first_card_is_fatal(predicted, hands_before)
    if not (G and G.GAME and G.GAME.blind and G.STAGE == G.STAGES.RUN) then return false end
    if G.GAME.won or R.phase or predicted == nil then return false end
    local round = G.GAME.current_round
    if not round then return false end
    if round.hands_left > 0 then return false end
    if hands_before ~= nil and hands_before > 1 then return false end
    local below = compare_below(predicted, G.GAME.blind.chips)
    if below ~= true then return false end
    if can_be_saved_by_bones(predicted) then return false end
    for _, fn in ipairs(R.rescue_checks) do
        local ok, saved = pcall(fn, predicted, G.GAME)
        if not ok or saved then return false end
    end
    return true
end

function R.begin()
    if R.phase ~= 'jiggle' or not (G and G.GAME and G.GAME.pseudorandom) then return end
    local run = G.GAME
    R.origin = {
        seed = run.pseudorandom.seed,
        stake = run.stake,
        seeded = run.seeded,
        challenge = run.challenge_tab,
        selected_back_key = run.selected_back_key and run.selected_back_key.key,
    }
    R.phase = 'freeze'
    R.visual_phase = 'hold'
    R.blackout_alpha = 0
    R.capture_generation = R.capture_generation + 1
    if R.frozen_image and R.frozen_image.release then R.frozen_image:release() end
    R.frozen_image = nil
    R.capture_image_data = nil
    R.capture_requested = false
    R.capture_requested_at = nil
    R.capture_failed = false
    R.freeze_started = nil
    R.restored = false
    R.rewind_started = love.timer.getTime()
    local selected_sfx = R.pick_sfx()
    R.sfx_seconds = selected_sfx.duration
    R.active_sfx = selected_sfx.key
    R.sound_started = R.rewind_started
    R.music_scale = 0
    R.first_card = nil
    R.jiggle_started = nil
    R.chips_feedback_at = nil
    R.chips_feedback_draws = 0
    if type(modulate_sound) == 'function' then modulate_sound(1 / 60) end
    play_sound(R.active_sfx, 1, 1)
end

local function rewind_game()
    local origin = R.origin
    if not origin then R.phase = 'playing'; return end
    R.phase = 'restarting'
    local choice = R.current_mode()
    local target
    local snapshot
    local ante = G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 1
    if choice == 'redo' then
        target = R.pick_checkpoint(ante, clamp_antes(cfg.antes_back))
        if target then snapshot = clone_save(R.history.checkpoints[target]) end
    end
    if snapshot then
        for recorded in pairs(R.history.checkpoints) do
            if type(recorded) == 'number' and recorded > target then R.history.checkpoints[recorded] = nil end
        end
        R.write_history()
        R.internal_start = true
        G:delete_run()
        G:start_run({savetext = snapshot})
        R.internal_start = false
    else
        G:delete_run()
        if G.GAME and origin.selected_back_key and G.P_CENTERS[origin.selected_back_key] then
            G.GAME.viewed_back = nil
            G.GAME.selected_back = Back(G.P_CENTERS[origin.selected_back_key])
        end
        local seed = origin.seed
        if choice == 'remake' then seed = nil end
        G:start_run({seed = seed, stake = origin.stake, challenge = origin.challenge})
        if choice ~= 'remake' and G.GAME then G.GAME.seeded = origin.seeded end
    end
    R.restored = true
    R.phase = 'freeze'
    R.origin = nil
end

function R.start_jiggle(from_score)
    if R.phase then return end
    R.phase = 'jiggle'
    R.jiggle_started = love.timer.getTime()
    R.jiggle_draws = 0
    if not from_score then
        local card = R.first_card or (G and G.play and G.play.cards and G.play.cards[1])
        if card and not card.REMOVED and type(card.juice_up) == 'function' then
            card:juice_up(0.7, 0.2)
        end
    end
end

local function smoothstep(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

function R.update_visual()
    if R.visual_phase == 'dissolve' and R.visual_started then
        local t = (love.timer.getTime() - R.visual_started) / R.reveal_seconds
        R.blackout_alpha = 1 - smoothstep(t)
        if t >= 1 then
            R.visual_phase = nil
            R.visual_started = nil
            R.blackout_alpha = 0
            if R.frozen_image and R.frozen_image.release then R.frozen_image:release() end
            R.frozen_image = nil
            R.capture_image_data = nil
            R.capture_requested = false
            R.capture_requested_at = nil
        end
    end
end

local function update_audio()
    if not R.sound_started then
        R.music_scale = 1
        return
    end
    local elapsed = love.timer.getTime() - R.sound_started
    if elapsed < R.sfx_seconds then
        R.music_scale = 0
    elseif elapsed < R.sfx_seconds + R.fade_seconds then
        R.music_scale = math.max(0, math.min(1, (elapsed - R.sfx_seconds) / R.fade_seconds))
        if R.phase == 'playing' then R.phase = 'fade' end
    else
        R.music_scale = 1
        R.sound_started = nil
        R.phase = nil
        R.rewind_started = nil
    end
end

local old_modulate_sound = modulate_sound
if type(old_modulate_sound) == 'function' then
    function modulate_sound(dt, ...)
        update_audio()
        if R.music_scale >= 1 or not (G and G.SETTINGS and G.SETTINGS.SOUND) then
            return old_modulate_sound(dt, ...)
        end
        local settings = G.SETTINGS.SOUND
        local before = settings.music_volume
        if type(before) ~= 'number' then return old_modulate_sound(dt, ...) end
        settings.music_volume = before * R.music_scale
        local ok, result = pcall(old_modulate_sound, dt, ...)
        settings.music_volume = before
        if not ok then error(result) end
        return result
    end
end

local function freeze_image(alpha)
    if not (R.frozen_image and love and love.graphics) then return false end
    local graphics = love.graphics
    local window_w, window_h = graphics.getDimensions()
    local image_w, image_h = R.frozen_image:getDimensions()
    graphics.push('all')
    graphics.origin()
    graphics.setCanvas()
    graphics.setShader()
    graphics.setScissor()
    graphics.setBlendMode('alpha', 'alphamultiply')
    graphics.setColor(1, 1, 1, alpha)
    graphics.draw(R.frozen_image, 0, 0, 0, window_w / image_w, window_h / image_h)
    graphics.pop()
    return true
end

local function make_freeze_image()
    if R.frozen_image or not R.capture_image_data then return end
    local image_data = R.capture_image_data
    R.capture_image_data = nil
    local ok, image = pcall(love.graphics.newImage, image_data)
    if ok and image then
        image:setFilter('linear', 'linear')
        R.frozen_image = image
        R.freeze_started = love.timer.getTime()
    else
        R.capture_requested = false
        R.capture_failed = true
    end
end

local function fallback_capture()
    if not (G and love and love.graphics) then return false end
    local graphics = love.graphics
    local source = G.AA_CANVAS or G.CANVAS
    if not source then return false end
    local ok, image = pcall(function()
        local width, height = graphics.getDimensions()
        local copy = graphics.newCanvas(width, height, {readable = true})
        graphics.push('all')
        graphics.origin()
        graphics.setCanvas(copy)
        graphics.setShader()
        graphics.setScissor()
        graphics.setBlendMode('alpha', 'alphamultiply')
        graphics.clear(0, 0, 0, 1)
        graphics.setColor(1, 1, 1, 1)
        graphics.draw(source, 0, 0, 0, width / source:getPixelWidth(), height / source:getPixelHeight())
        graphics.pop()
        return copy
    end)
    if ok and image then
        R.frozen_image = image
        R.freeze_started = love.timer.getTime()
        return true
    end
    return false
end

local old_game_update = Game.update
function Game:update(dt, ...)
    R.update_visual()
    if R.phase == 'freeze' then
        update_audio()
        make_freeze_image()
        if not R.frozen_image then
            if type(modulate_sound) == 'function' then modulate_sound(dt) end
            return
        end
        if not R.restored then
            rewind_game()
        end
        if R.restored and love.timer.getTime() - R.freeze_started >= R.freeze_seconds then
            R.phase = 'playing'
            R.visual_phase = 'dissolve'
            R.visual_started = love.timer.getTime()
            R.blackout_alpha = 1
        end
        return old_game_update(self, dt, ...)
    end
    return old_game_update(self, dt, ...)
end

local old_game_draw = Game.draw
if type(old_game_draw) == 'function' then
    function Game:draw(...)
        if R.phase == 'freeze' then
            if R.frozen_image then
                freeze_image(1)
                return
            end
            local result = old_game_draw(self, ...)
            if not R.capture_requested then
                R.capture_requested = true
                R.capture_requested_at = love.timer.getTime()
                local generation = R.capture_generation
                local ok = pcall(function()
                    love.graphics.captureScreenshot(function(image_data)
                        if generation == R.capture_generation and R.phase == 'freeze' and not R.frozen_image then
                            R.capture_image_data = image_data
                        end
                    end)
                end)
                if not ok then
                    R.capture_failed = true
                end
            end
            if not R.frozen_image and (R.capture_failed or (R.capture_requested_at and love.timer.getTime() - R.capture_requested_at >= 0.35)) then
                fallback_capture()
            end
            return result
        end
        local result = old_game_draw(self, ...)
        R.update_visual()
        if R.visual_phase == 'dissolve' and R.frozen_image then
            freeze_image(R.blackout_alpha)
        end
        if R.phase == 'jiggle' then
            R.jiggle_draws = R.jiggle_draws + 1
            if R.chips_feedback_at then R.chips_feedback_draws = R.chips_feedback_draws + 1 end
        end
        return result
    end
end

local old_start_run = Game.start_run
function Game:start_run(args, ...)
    local result = old_start_run(self, args, ...)
    local game = G and G.GAME
    if game then
        if args and args.savetext then
            if not game.rbd_run_id then
                game.rbd_run_id = tostring(game.pseudorandom and game.pseudorandom.seed or '')..':legacy:'..tostring(os.time())..':'..tostring(love.timer.getTime())
            end
            if not R.history or R.history.run_id ~= game.rbd_run_id then
                R.history = load_history(game.rbd_run_id) or {run_id = game.rbd_run_id, checkpoints = {}}
            end
        else
            forget_history()
            game.rbd_run_id = tostring(game.pseudorandom and game.pseudorandom.seed or '')..':'..tostring(os.time())..':'..tostring(love.timer.getTime())
            R.history = {run_id = game.rbd_run_id, checkpoints = {}}
        end
    end
    R.install_evaluate_hook()
    return result
end

function R.install_evaluate_hook()
    if not (G and G.FUNCS and type(G.FUNCS.evaluate_play) == 'function') then return end
    if G.FUNCS.evaluate_play == R.installed_evaluator then return end
    local previous_evaluate = G.FUNCS.evaluate_play
    local wrapped = function(e, ...)
        if R.phase or not (G and G.E_MANAGER and G.GAME) then
            return previous_evaluate(e, ...)
        end
        R.checkpoint = nil
        R.score_event_index = nil
        R.chips_event_index = nil
        R.chips_feedback_at = nil
        R.chips_feedback_draws = 0
        R.first_card = nil
        R.scoring_now = true
        local recorded_score
        local last_hands = R.last_hands_before
        R.last_hands_before = nil
        local event_manager = G.E_MANAGER
        local old_add_event = event_manager.add_event
        event_manager.add_event = function(self, event, ...)
            if event and event.ease and event.ease.ref_table == G.GAME and event.ease.ref_value == 'chips' then
                recorded_score = event.ease.end_val
            end
            return old_add_event(self, event, ...)
        end
        local previous_status = card_eval_status_text
        if type(previous_status) == 'function' then
            card_eval_status_text = function(card, eval_type, ...)
                local tracked_card = R.scoring_now and R.first_card == card
                local first_chips = tracked_card and eval_type == 'chips' and not R.chips_event_index
                local fallback_status = tracked_card and not R.score_event_index
                local base = event_manager.queues and event_manager.queues.base
                local before = (first_chips or fallback_status) and base and #base
                local result = previous_status(card, eval_type, ...)
                if before and base and #base > before then
                    if fallback_status then R.score_event_index = #base end
                    if first_chips then
                        local feedback_event = base[#base]
                        if feedback_event and type(feedback_event.func) == 'function' then
                            R.chips_event_index = #base
                            local status_func = feedback_event.func
                            feedback_event.func = function(...)
                                local status_done = status_func(...)
                                if status_done ~= false and not R.chips_feedback_at then
                                    R.chips_feedback_at = love.timer.getTime()
                                    R.chips_feedback_draws = 0
                                end
                                return status_done
                            end
                        end
                    end
                end
                return result
            end
        end
        local ok, outcome = pcall(previous_evaluate, e, ...)
        if type(previous_status) == 'function' then card_eval_status_text = previous_status end
        event_manager.add_event = old_add_event
        R.scoring_now = false
        if not ok then error(outcome) end
        local fatal = first_card_is_fatal(recorded_score, last_hands)
        if fatal then
            local queue = event_manager.queues and event_manager.queues.base
            if queue then
                local checkpoint = R.checkpoint
                local index = (R.chips_event_index or R.score_event_index or checkpoint)
                index = index and math.min(#queue + 1, index + 1) or 1
                local used_score_event = R.score_event_index ~= nil
                local must_show_chips = R.chips_event_index ~= nil
                local barrier = Event({
                    trigger = 'immediate',
                    func = function()
                        if not R.phase then R.start_jiggle(used_score_event) end
                        local feedback_ready = not must_show_chips or (
                            R.chips_feedback_at and R.chips_feedback_draws >= 3 and
                            love.timer.getTime() - R.chips_feedback_at >= R.jiggle_seconds)
                        if R.phase == 'jiggle' and feedback_ready and
                            R.jiggle_draws >= 3 and R.jiggle_started and
                            love.timer.getTime() - R.jiggle_started >= R.jiggle_seconds then
                            R.begin()
                        end
                        return R.phase == nil
                    end
                })
                table.insert(queue, index, barrier)
            end
        end
        R.checkpoint = nil
        R.score_event_index = nil
        R.chips_event_index = nil
        if not fatal then R.first_card = nil end
        return outcome
    end
    R.installed_evaluator = wrapped
    G.FUNCS.evaluate_play = wrapped
end

if G and G.FUNCS then
    local old_play = G.FUNCS.play_cards_from_highlighted
    if type(old_play) == 'function' then
        G.FUNCS.play_cards_from_highlighted = function(e, ...)
            if G and G.GAME and G.GAME.current_round then
                R.last_hands_before = G.GAME.current_round.hands_left
            end
            return old_play(e, ...)
        end
    end
end

R.install_evaluate_hook()
