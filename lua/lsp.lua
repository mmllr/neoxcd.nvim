local M = {}

---@class lsp.types
M.types = {}

---@alias lsp.types.SymbolKind 1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26

---@class lsp.types.Symbol
---@field name string
---@field kind lsp.types.SymbolKind
---@field range lsp.types.Range
---@field children? lsp.types.Symbol[]

---@class lsp.types.Position
---@field line integer Line position in a document (zero-based).  If a line number is greater than the number of lines in a document, it defaults back to the number of lines in the document. If a line number is negative, it defaults to 0.
---@field character integer Character offset on a line in a document (zero-based).  The meaning of this offset is determined by the negotiated `PositionEncodingKind`.  If the character value is greater than the line length it defaults back to the line length.

---@class lsp.types.Range
---@field start lsp.types.Position The range's start position.
---@field end lsp.types.Position The range's end position.

---Requests the LSP server for document symbols
---@async
---@param buf integer
---@return lsp.types.Symbol[]|nil
function M.document_symbol(buf)
  return nil
end

return M
