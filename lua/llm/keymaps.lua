local completion = require("llm.completion")
local config = require("llm.config")

local M = {
  setup_done = false,
}

local function accept_suggestion()
  if not completion.suggestion then
    return
  end
  vim.schedule(completion.complete)
end

local function accept_word()
  if not completion.suggestion then
    return
  end
  vim.schedule(completion.accept_word)
end

local function accept_line()
  if not completion.suggestion then
    return
  end
  vim.schedule(completion.accept_line)
end

local function dismiss_suggestion()
  if not completion.suggestion then
    return
  end
  vim.schedule(function()
    completion.cancel()
    completion.suggestion = nil
  end)
end

function M.setup()
  if M.setup_done then
    return
  end

  local accept_keymap = config.get().accept_keymap
  local accept_word_keymap = config.get().accept_word_keymap
  local accept_line_keymap = config.get().accept_line_keymap
  local dismiss_keymap = config.get().dismiss_keymap

  vim.keymap.set("i", accept_keymap, accept_suggestion, { expr = true })

  vim.keymap.set("n", accept_keymap, accept_suggestion, { expr = true })

  vim.keymap.set("i", accept_word_keymap, accept_word, { expr = true })

  vim.keymap.set("n", accept_word_keymap, accept_word, { expr = true })

  vim.keymap.set("i", accept_line_keymap, accept_line, { expr = true })

  vim.keymap.set("n", accept_line_keymap, accept_line, { expr = true })

  vim.keymap.set("i", dismiss_keymap, dismiss_suggestion, { expr = true })

  vim.keymap.set("n", dismiss_keymap, dismiss_suggestion, { expr = true })

  M.setup_done = true
end

return M
