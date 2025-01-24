local api = vim.api
local augroup = "llm.suggestion"
local llm_ls = require("llm.language_server")
local config = require("llm.config")
local fn = vim.fn
local utils = require("llm.utils")

local M = {
  setup_done = false,

  hl_group = "LLMSuggestion",
  ns_id = api.nvim_create_namespace("llm.suggestion"),
  request_id = nil,
  shown_suggestion = nil,
  suggestion = nil,
  suggestions_enabled = true,
  timer = nil,
}

local function new_cursor_pos(lines, row)
  local lines_len = #lines
  local row_offset = row + lines_len - 1
  local col_offset = string.len(lines[lines_len])

  return row_offset, col_offset
end

local function stop_timer()
  if M.timer then
    fn.timer_stop(M.timer)
    M.timer = nil
  end
end

local function cancel_request()
  if M.request_id then
    llm_ls.cancel_request(M.request_id)
    M.request_id = nil
  end
end

local function clear_preview()
  api.nvim_buf_clear_namespace(0, M.ns_id, 0, -1)
end

function M.cancel()
  stop_timer()
  cancel_request()
  clear_preview()
end

function M.reject()
  M.cancel()
  if M.shown_suggestion ~= nil then
    llm_ls.reject_completion(M.shown_suggestion)
    M.shown_suggestion = nil
  end
end

function M.schedule()
  M.reject()

  M.timer = fn.timer_start(config.get().debounce_ms, function()
    if fn.mode() == "i" then
      M.lsp_suggest()
    end
  end)
end

function M.lsp_suggest()
  M.request_id = llm_ls.get_completions(function(err, result, context, _conf)
    if err ~= nil then
      vim.notify("[LLM] " .. err.message, vim.log.levels.ERROR)
      return
    end
    M.wes_last_result = result
    local completions = result.completions
    local generated_text = llm_ls.extract_generation(completions)
    local lines = utils.split_str(generated_text, "\n")
    if lines == nil then
      return
    end
    M.suggestion = lines
    local col = context.params.position.character
    local line = context.params.position.line

    function show_extmark()
      local extmark = {
        virt_text_win_col = col,
        virt_text = { { lines[1], M.hl_group } },
      }
      if #lines > 1 then
        extmark.virt_lines = {}
        for i = 2, #lines do
          extmark.virt_lines[i - 1] = { { lines[i], M.hl_group } }
        end
      end
      api.nvim_buf_set_extmark(0, M.ns_id, line, col, extmark)
    end
    show_extmark()

    M.shown_suggestion = result
  end)
end

function M.complete()
  M.cancel()

  if M.suggestion ~= nil then
    local r, c = utils.get_cursor_pos()
    local line = api.nvim_buf_get_lines(0, r - 1, r, false)[1]

    -- rebuild the current line w/ the suggestion
    M.suggestion[1] = utils.insert_at(line, c + 1, M.suggestion[1])
    -- only the first line needs to be inserted? (in between code?! for FITM in this line.. wouldn't that be an issue for next lines too?!) ... is that why they limit to single line if FITM?
    -- rest of lines are inserted after current line

    -- determine new cursor position based on all added line(s) => set to length of last line inserted
    local row_offset, col_offset = new_cursor_pos(M.suggestion, r)

    -- insert suggestion line(s) ... remember first line is merged w/ original, thus r-1 here to get rid of original line
    api.nvim_buf_set_lines(0, r - 1, r, false, M.suggestion)

    -- move cursor
    api.nvim_win_set_cursor(0, { row_offset, col_offset })

    -- tell LLM accepted completion (just for info logging)
    llm_ls.accept_completion(M.shown_suggestion)

    -- reset to no suggestion (along with M.cancel() above)
    M.shown_suggestion = nil -- FYI this is only used for sending to server in info log after accept
    M.suggestion = nil
  end
end

function M.accept_word()
  print("TODO ME PLEASE")
end

function M.accept_line()
  -- TODO BEHAVIORS:
  -- - single line suggestion => move cursor to end of current line
  -- - multi line suggest => accept line moves cursor to end of current line (first), then for subsequent lines it moves to start of next line
  --    try this in vscode, it feels right how its done there
  --    I might want accept line to always go to next line though?? thoughts (I don't like the accept line => end of line => accept line => next line start => accept line => next2 line start
  -- - accept word => moves cursor to end of inserted word (right after)
  -- HOLD DOWN:
  --   I WANT TO BE ABLE TO HOLD DOWN accept word (alt+right) and have it machine gun its way through, blocking on each part of course (milliseconds of blocking of course)
  --   I MAY  want the same for lines though thats gonna be less important as usually few lines suggested

  M.cancel() -- TODO verify - IIAC this safe to use w/ partial completions or would this nuke anything?

  -- start with taking a line/word
  -- NOT CANCEL IT
  if M.suggestion ~= nil then
    local r, c = utils.get_cursor_pos()
    local line = api.nvim_buf_get_lines(0, r - 1, r, false)[1]

    -- rebuild the current line w/ the suggestion
    -- only the first line needs to be inserted? (in between code?! for FITM in this line.. wouldn't that be an issue for next lines too?!) ... is that why they limit to single line if FITM?
    M.suggestion[1] = utils.insert_at(line, c + 1, M.suggestion[1])
    -- rest of lines are inserted after current line

    -- "" is for second (new) line... and this just works!
    local accepted_line = { M.suggestion[1], "" }
    -- PRN how do I trigger the tab indent thingy? DO I EVEN WANT IT HERE? retry this as is when I get suggestion to refresh
    --    IIRC vscode moves to start of new line BTW... col 0

    -- insert line(s)
    api.nvim_buf_set_lines(0, r - 1, r, false, accepted_line)

    -- move cursor position
    local row_offset, col_offset = new_cursor_pos(accepted_line, r)
    M.suspend_cursor_moved = true -- TODO DO NOT TRIGGER NEW SUGGESTION!!!
    api.nvim_win_set_cursor(0, { row_offset, col_offset })
    M.suspend_cursor_moved = false

    -- tell LLM accepted completion (just for info logging)
    -- llm_ls.accept_completion(M.shown_suggestion)

    if #M.suggestion > 1 then
      table.remove(M.suggestion, 1)
      -- TODO refresh display of suggestion
      -- M.shown_suggestion = -- entire result, just leave it all intact as I dont care right now
    else
      M.suggestion = nil
      M.shown_suggestion = nil
    end
  end
end

M.suspend_cursor_moved = false

function M.should_complete()
  return M.suggestions_enabled
end

function M.toggle_suggestion()
  M.suggestions_enabled = not M.suggestions_enabled
  local state = M.suggestions_enabled and "on" or "off"
  vim.notify("[LLM] Auto suggestions are " .. state, vim.log.levels.INFO)
end

function M.create_autocmds()
  api.nvim_create_augroup(augroup, { clear = true })

  api.nvim_create_autocmd("InsertLeave", { pattern = "*", callback = M.reject })

  api.nvim_create_autocmd("CursorMovedI", {
    pattern = config.get().enable_suggestions_on_files,
    callback = function()
      if M.suspend_cursor_moved then
        return
      end
      if M.should_complete() then
        M.schedule()
      else
        M.reject()
        M.suggestion = nil
      end
    end,
  })
end

function M.setup(suggestions_enabled)
  if M.setup_done then
    return
  end

  vim.api.nvim_command("highlight default link " .. M.hl_group .. " Comment")

  M.suggestions_enabled = suggestions_enabled
  M.setup_done = true
end

return M
