#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { NotesApiClient, ApiError } from "./api-client.js";

// ── Configuration ──

const NOTES_API_URL = process.env.NOTES_API_URL;
const NOTES_EMAIL = process.env.NOTES_EMAIL;
const NOTES_PASSWORD = process.env.NOTES_PASSWORD;

if (!NOTES_API_URL || !NOTES_EMAIL || !NOTES_PASSWORD) {
  console.error(
    "Missing required environment variables: NOTES_API_URL, NOTES_EMAIL, NOTES_PASSWORD"
  );
  process.exit(1);
}

const client = new NotesApiClient({
  baseUrl: NOTES_API_URL,
  email: NOTES_EMAIL,
  password: NOTES_PASSWORD,
});

// ── Helpers ──

function toolResult(data: unknown): { content: { type: "text"; text: string }[] } {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }],
  };
}

function toolError(err: unknown): { content: { type: "text"; text: string }[]; isError: true } {
  const message =
    err instanceof ApiError
      ? `API error (${err.status}): ${err.message}`
      : err instanceof Error
        ? err.message
        : String(err);

  return {
    content: [{ type: "text" as const, text: message }],
    isError: true,
  };
}

// ── MCP Server ──

const server = new McpServer({
  name: "notes",
  version: "1.0.0",
});

// ── Note Tools ──

server.tool(
  "list_notes",
  "List notes. Optionally filter by status (pinned, archived, trash) or tag name. Supports sorting and pagination.",
  {
    filter: z
      .enum(["pinned", "archived", "trash"])
      .optional()
      .describe("Filter notes by status"),
    tag: z.string().optional().describe("Filter by tag name"),
    sort: z
      .enum(["created_at", "title"])
      .optional()
      .describe("Sort field"),
    direction: z
      .enum(["asc", "desc"])
      .optional()
      .describe("Sort direction"),
    page: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Page number for pagination"),
  },
  async (args) => {
    try {
      const result = await client.listNotes({
        filter: args.filter,
        tag: args.tag,
        sort: args.sort,
        direction: args.direction,
        page: args.page?.toString(),
      });
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "get_note",
  "Get a single note by its ID, including its tags, shared users, and full body content.",
  {
    id: z.number().int().positive().describe("Note ID"),
  },
  async (args) => {
    try {
      const result = await client.getNote(args.id);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "create_note",
  "Create a new note with a title and/or body (markdown). Optionally pin it and assign tag IDs.",
  {
    title: z.string().optional().describe("Note title"),
    body: z.string().optional().describe("Note body (markdown)"),
    pinned: z.boolean().optional().describe("Pin the note"),
    tag_ids: z
      .array(z.number().int().positive())
      .optional()
      .describe("Array of tag IDs to assign"),
  },
  async (args) => {
    try {
      const result = await client.createNote(args);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "update_note",
  "Update an existing note's title, body, pinned status, or tags.",
  {
    id: z.number().int().positive().describe("Note ID"),
    title: z.string().optional().describe("New title"),
    body: z.string().optional().describe("New body (markdown)"),
    pinned: z.boolean().optional().describe("Pin/unpin the note"),
    tag_ids: z
      .array(z.number().int().positive())
      .optional()
      .describe("Replace tag IDs"),
  },
  async (args) => {
    try {
      const { id, ...data } = args;
      const result = await client.updateNote(id, data);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "delete_note",
  "Move a note to trash (soft delete). If already trashed, permanently deletes it.",
  {
    id: z.number().int().positive().describe("Note ID"),
  },
  async (args) => {
    try {
      const result = await client.deleteNote(args.id);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "search_notes",
  "Find notes whose title or body contains every word of the query. Returns whole non-trashed notes, most recently updated first. " +
    "To find what the notes say about a topic or to ground an answer, use retrieve_passages instead: " +
    "it matches meaning as well as wording, ranks by relevance, and returns only the relevant excerpts.",
  {
    query: z
      .string()
      .min(1)
      .describe("Words every matching note must contain, in plain words (no search syntax)"),
    page: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Page number for pagination"),
  },
  async (args) => {
    try {
      const result = await client.searchNotes(
        args.query,
        args.page?.toString()
      );
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "retrieve_passages",
  "Retrieve the passages from the user's notes most relevant to a query, matched by meaning as well as wording, best first. " +
    "Use this to ground answers in the user's notes. Each passage carries its text, the headings enclosing it, and its note " +
    "(id, title, tags, timestamps, archived, owned or shared, web link); cite the note and headings, and use get_note for a note's full content. " +
    "Covers owned and shared notes, archived included, never trashed ones.",
  {
    query: z.string().min(1).describe("What to look for, in plain words"),
    tag: z.string().optional().describe("Only notes with this tag name"),
    archived: z
      .enum(["include", "exclude", "only"])
      .optional()
      .describe("Whether to include archived notes (default include)"),
    updated_after: z
      .string()
      .optional()
      .describe("Only notes updated at or after this ISO 8601 date or date-time"),
    updated_before: z
      .string()
      .optional()
      .describe("Only notes updated before this ISO 8601 date or date-time"),
    limit: z
      .number()
      .int()
      .min(1)
      .max(50)
      .optional()
      .describe("Maximum passages to return (default 8, at most 3 per note)"),
  },
  async (args) => {
    try {
      const result = await client.retrievePassages({
        q: args.query,
        tag: args.tag,
        archived: args.archived,
        updated_after: args.updated_after,
        updated_before: args.updated_before,
        limit: args.limit?.toString(),
      });
      const content = toolResult(result).content;
      if (result.ranking === "keyword") {
        content.unshift({
          type: "text" as const,
          text: "Note: semantic matching was unavailable, so these passages matched on wording only. If nothing fits, retry with words the notes are likely to contain.",
        });
      }
      return { content };
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "pin_note",
  "Toggle the pinned status of a note. Pinned notes appear at the top of the list.",
  {
    id: z.number().int().positive().describe("Note ID"),
  },
  async (args) => {
    try {
      const result = await client.togglePin(args.id);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "archive_note",
  "Archive a note. Archived notes are hidden from the main list but not deleted.",
  {
    id: z.number().int().positive().describe("Note ID"),
  },
  async (args) => {
    try {
      const result = await client.archiveNote(args.id);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "unarchive_note",
  "Unarchive a note, returning it to the main notes list.",
  {
    id: z.number().int().positive().describe("Note ID"),
  },
  async (args) => {
    try {
      const result = await client.unarchiveNote(args.id);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "restore_note",
  "Restore a note from trash back to the main notes list.",
  {
    id: z.number().int().positive().describe("Note ID"),
  },
  async (args) => {
    try {
      const result = await client.restoreNote(args.id);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "list_trash",
  "List all notes currently in the trash.",
  {
    page: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Page number for pagination"),
  },
  async (args) => {
    try {
      const result = await client.listTrash(args.page?.toString());
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

// ── Tag Tools ──

server.tool(
  "list_tags",
  "List all tags belonging to the current user.",
  {},
  async () => {
    try {
      const result = await client.listTags();
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "create_tag",
  "Create a new tag with a name and optional hex color (e.g. #ff5733).",
  {
    name: z.string().min(1).describe("Tag name"),
    color: z
      .string()
      .regex(/^#[0-9a-fA-F]{6}$/)
      .optional()
      .describe("Hex color code (e.g. #ff5733)"),
  },
  async (args) => {
    try {
      const result = await client.createTag(args);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

// ── Share Tools ──

server.tool(
  "list_shares",
  "List all users that a note is shared with.",
  {
    note_id: z.number().int().positive().describe("Note ID"),
  },
  async (args) => {
    try {
      const result = await client.listShares(args.note_id);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "share_note",
  "Share a note with another user by email. Only the note owner can share.",
  {
    note_id: z.number().int().positive().describe("Note ID"),
    email: z.string().email().describe("Email of the user to share with"),
  },
  async (args) => {
    try {
      const result = await client.shareNote(args.note_id, args.email);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

server.tool(
  "revoke_share",
  "Revoke a user's access to a shared note. Only the note owner can revoke.",
  {
    note_id: z.number().int().positive().describe("Note ID"),
    share_id: z.number().int().positive().describe("Share ID to revoke"),
  },
  async (args) => {
    try {
      const result = await client.revokeShare(args.note_id, args.share_id);
      return toolResult(result);
    } catch (err) {
      return toolError(err);
    }
  }
);

// ── Start ──

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
