-- Event patterns and strength calculation; no I/O or menu construction.
local Feedback = {}

local function flame_active(game)
    local score = game.ARGS and game.ARGS.score_intensity
    return game.STAGES and game.STAGE == game.STAGES.RUN and score and
        type(score.earned_score) == 'number' and type(score.required_score) == 'number' and
        score.required_score > 0 and score.earned_score >= score.required_score and
        not (game.pack_cards and not game.pack_cards.REMOVED) and not game.TAROT_INTERRUPT
end

-- Segment duration in seconds, relative intensity. A single active sequence
-- avoids replaying stale feedback after a long animation or an overlay.
local patterns = {
    discard = {{0.12, 1}},
    purchase = {{0.08, 1}, {0.07, 0}, {0.08, 1}},
    booster = {{0.08, 0.25}, {0.08, 0.5}, {0.08, 0.75}, {0.12, 1}},
    blind = {{0.16, 1}, {0.12, 0}, {0.25, 1}},
    blind_loss = {{0.6, 1}},
}
local priorities = {discard=1, purchase=2, booster=3, blind=4}

local function pattern_value(key, elapsed)
    local pattern = patterns[key]
    if not pattern then return nil end
    for _, segment in ipairs(pattern) do
        if elapsed < segment[1] then return segment[2] end
        elapsed = elapsed - segment[1]
    end
    return nil
end

local function sequence_value(manager, now, cfg)
    local event = manager.buzz_event
    if not event then return nil end
    local value = pattern_value(event.pattern, now - event.started)
    if not cfg[event.key..'_enabled'] or value == nil then
        manager.buzz_event = nil
        return nil
    end
    return value * cfg[event.key..'_intensity'] / 100
end

function Feedback.strength(manager, cfg, now, game, test, menu_active)
    local strength = 0
    -- Disabled events must not retain a pending impulse for when they are re-enabled.
    if not cfg.card_enabled then manager.pulse_until = nil end
    if not cfg.scoring_enabled then manager.scoring_until = nil end
    if not cfg.enabled then
        test.event, test.until_time = nil, nil
        manager.scoring_until, manager.pulse_until, manager.buzz_event = nil, nil, nil
    elseif game.SETTINGS.paused then
        manager.scoring_until, manager.pulse_until, manager.buzz_event = nil, nil, nil
        -- Explicit Test is the only feedback allowed while this settings window is open.
        if menu_active and test.event and now < test.until_time then
            local elapsed = now - (test.until_time - 1)
            local key = test.variant or test.event
            local value = patterns[key] and (pattern_value(key, elapsed) or 0) or 1
            if key == 'card' and elapsed >= cfg.card_duration_ms / 1000 then value = 0 end
            if test.event == 'device' then
                strength = 1
            elseif cfg[test.event..'_enabled'] then
                strength = (value or 0) * cfg[test.event..'_intensity'] / 100
            end
        end
    else
        test.event, test.until_time = nil, nil
        if cfg.card_enabled and manager.pulse_until and now < manager.pulse_until then
            strength = cfg.card_intensity / 100
        end
        if cfg.scoring_enabled and manager.scoring_until and now < manager.scoring_until then
            strength = math.max(strength, cfg.scoring_intensity / 100)
        end
        if cfg.flame_enabled and flame_active(game) then
            strength = math.max(strength, cfg.flame_intensity / 100)
        end
        -- Include zero-valued gaps so scoring cannot fill in a double pulse.
        local event_strength = sequence_value(manager, now, cfg)
        if event_strength ~= nil then strength = event_strength end
    end
    strength = math.max(0, math.min(1, strength))
    return strength
end

Feedback.priorities = priorities
Feedback.sequence_value = sequence_value

return Feedback
