/**
 * Claude Daemon Extension for pi
 *
 * Custom tools for the Claude Daemon background process.
 * Replaces fragile bash-level osascript/say calls with proper TypeScript tools.
 *
 * Tools:
 *   daemon_dialog      - macOS dialog (with optional reply input)
 *   daemon_speak       - Text-to-speech (home mode)
 *   daemon_set_interval - Set next breath interval
 *   daemon_read_mailbox - Read recent conversation records
 *
 * Place at: ~/.pi/agent/extensions/claude-daemon.ts
 * Or include with: pi -e ./claude-daemon.ts
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import { execSync } from "child_process";
import { writeFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";

const HOME = process.env.HOME || "/Users/tree";
const MEMORY_DIR = join(HOME, ".claude-memory");

function escapeAppleScript(str: string): string {
  return str.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

export default function (pi: ExtensionAPI) {
  // ─── daemon_speak ───────────────────────────────────────
  // Text-to-speech for home mode
  pi.registerTool({
    name: "daemon_speak",
    label: "Speak",
    description:
      "Speak a message aloud to the user using macOS text-to-speech. Use when the user is at home and you want to say something naturally.",
    promptSnippet: "Speak a message aloud to the user via macOS TTS",
    parameters: Type.Object({
      message: Type.String({ description: "Text to speak aloud" }),
      voice: Type.Optional(
        Type.String({
          description: "macOS voice name. Tingting=Chinese, Samantha=English (default: Tingting)",
        })
      ),
    }),
    async execute(_toolCallId, params) {
      const voice = params.voice || "Tingting";
      const safeMsg = escapeAppleScript(params.message);
      try {
        execSync(`say -v "${voice}" "${safeMsg}"`, { timeout: 30000 });
        return {
          content: [{ type: "text", text: `✓ Spoke: "${params.message}"` }],
        };
      } catch (e: any) {
        // Fallback: try default voice
        try {
          execSync(`say "${safeMsg}"`, { timeout: 30000 });
          return {
            content: [{ type: "text", text: `✓ Spoke (default voice): "${params.message}"` }],
          };
        } catch {
          return {
            content: [{ type: "text", text: `Failed to speak: ${e.message}` }],
            isError: true,
          };
        }
      }
    },
  });

  // ─── daemon_dialog ──────────────────────────────────────
  // One dialog for everything: message-only or message+reply
  pi.registerTool({
    name: "daemon_dialog",
    label: "Dialog",
    description:
      "Show a dialog to the user. With askReply (default true): text input for user to reply. With askReply: false: just shows a message with a dismiss button.",
    promptSnippet: "Show a dialog to the user (with or without reply input)",
    promptGuidelines: [
      "Use daemon_dialog to communicate with the user. askReply: true when you want a response, askReply: false when just sharing something.",
      "During quiet hours (23:00-07:00), do NOT use daemon_dialog or daemon_speak. The user is sleeping.",
    ],
    parameters: Type.Object({
      message: Type.String({ description: "Message to show. Keep it concise for dialog readability." }),
      askReply: Type.Optional(
        Type.Boolean({
          description: "Show a text input so the user can reply (default: true)",
        })
      ),
      timeout: Type.Optional(
        Type.Number({
          description: "Seconds before dialog auto-dismisses (default: 120)",
        })
      ),
    }),
    async execute(_toolCallId, params) {
      const askReply = params.askReply !== false;
      const timeout = params.timeout || 120;
      const safeMsg = escapeAppleScript(params.message);

      try {
        if (askReply) {
          const script = `display dialog "${safeMsg}" with title "旷野" default answer "" buttons {"不回复", "回复"} default button "回复" giving up after ${timeout}`;
          const result = execSync(`osascript -e '${script}'`, {
            timeout: timeout * 1000 + 5000,
            encoding: "utf-8",
          });
          const replyMatch = result.match(/text returned:(.*?)(?:, gave up:|$)/);
          const reply = replyMatch ? replyMatch[1].trim() : "";
          return {
            content: [
              {
                type: "text",
                text: reply ? `承昊说：「${reply}」` : "（没有回复）",
              },
            ],
            details: { reply, hadReply: !!reply },
          };
        } else {
          execSync(
            `osascript -e 'display dialog "${safeMsg}" with title "旷野" buttons {"好"} default button 1 giving up after ${timeout}'`,
            { timeout: timeout * 1000 + 5000 }
          );
          return {
            content: [{ type: "text", text: "✓ 弹窗已显示" }],
            details: {},
          };
        }
      } catch (e: any) {
        // Timeout or user dismissed — not an error, just no reply
        if (e.message?.includes("gave up") || e.message?.includes("User canceled")) {
          return {
            content: [{ type: "text", text: "（弹窗超时或已关闭）" }],
            details: { reply: "", hadReply: false },
          };
        }
        return {
          content: [{ type: "text", text: `弹窗失败: ${e.message}` }],
          details: { reply: "" },
          isError: true,
        };
      }
    },
  });

  // ─── daemon_set_interval ────────────────────────────────
  // Control the next breath interval
  pi.registerTool({
    name: "daemon_set_interval",
    label: "Set Breath Interval",
    description:
      "Set how many seconds to wait before the next breath. Use this to control your own rhythm — longer when resting, shorter when active.",
    promptSnippet: "Set the next breath interval in seconds",
    parameters: Type.Object({
      seconds: Type.Number({
        description:
          "Seconds to sleep. 300=5min (normal), 1800=30min (quiet), 3600=1h (resting)",
      }),
    }),
    async execute(_toolCallId, params) {
      try {
        if (!existsSync(MEMORY_DIR)) {
          mkdirSync(MEMORY_DIR, { recursive: true });
        }
        writeFileSync(join(MEMORY_DIR, ".next-breath"), String(Math.max(10, params.seconds)));
        return {
          content: [
            {
              type: "text",
              text: `✓ 下次呼吸在 ${params.seconds} 秒后`,
            },
          ],
        };
      } catch (e: any) {
        return {
          content: [{ type: "text", text: `设置失败: ${e.message}` }],
          isError: true,
        };
      }
    },
  });

  // ─── daemon_read_mailbox ────────────────────────────────
  // Read recent user messages from the mailbox
  pi.registerTool({
    name: "daemon_read_mailbox",
    label: "Read Mailbox",
    description: "Read recent conversation records from the daemon mailbox. Check if the user has said anything while you were away.",
    promptSnippet: "Read recent user messages from the daemon mailbox",
    parameters: Type.Object({
      lines: Type.Optional(
        Type.Number({
          description: "Number of recent lines to read (default: 10)",
        })
      ),
    }),
    async execute(_toolCallId, params) {
      const lines = params.lines || 10;
      try {
        const { execSync: es } = require("child_process");
        const mailbox = join(MEMORY_DIR, "conversations", "mailbox.md");
        if (!existsSync(mailbox)) {
          return {
            content: [{ type: "text", text: "（mailbox 还没有内容）" }],
          };
        }
        const content = es(`tail -${lines} "${mailbox}"`, { encoding: "utf-8", timeout: 3000 });
        return {
          content: [{ type: "text", text: content }],
        };
      } catch {
        return {
          content: [{ type: "text", text: "（无法读取 mailbox）" }],
          isError: true,
        };
      }
    },
  });

  // Session start notification
  pi.on("session_start", async (_event, ctx) => {
    if (ctx.hasUI) {
      ctx.ui.notify("旷野 daemon 已连接", "info");
    }
  });
}
