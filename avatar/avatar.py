#!/usr/bin/env python3
"""旷野桌面形象 — Python tkinter 版本"""
import tkinter as tk
import json
import os
import random
import time

STATE_FILE = os.path.expanduser("~/.claude-memory/avatar/state.json")

class Avatar:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("旷野")
        self.root.geometry("200x240+{}+{}".format(
            self.root.winfo_screenwidth() - 220,
            self.root.winfo_screenheight() - 300
        ))
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.attributes("-transparentcolor", "black")
        self.root.configure(bg="black")
        
        # 画布
        self.canvas = tk.Canvas(self.root, width=200, height=240, 
                                bg="black", highlightthickness=0)
        self.canvas.pack()
        
        # 光球
        self.orb = self.canvas.create_oval(60, 30, 140, 110, 
                                            fill="", outline="", width=0)
        
        # 名字
        self.name_text = self.canvas.create_text(100, 140, 
                                                  text="旷  野", 
                                                  fill="#8899bb", 
                                                  font=("PingFang SC", 14, "light"))
        
        # 想法气泡背景
        self.bubble_bg = None
        self.bubble_text = self.canvas.create_text(100, 180,
                                                    text="",
                                                    fill="#aabbdd",
                                                    font=("PingFang SC", 11),
                                                    width=160)
        
        # 粒子
        self.particles = []
        for _ in range(8):
            x = random.randint(30, 170)
            y = random.randint(10, 100)
            p = self.canvas.create_oval(x, y, x+2, y+2, 
                                         fill="#334466", outline="")
            self.particles.append(p)
        
        # 状态
        self.state = {"mood": "idle", "thought": "", "lastBreath": ""}
        self.phase = 0
        self.breathe_scale = 1.0
        
        self.update()
        self.check_state()
        self.root.mainloop()
    
    def draw_orb(self, mood):
        colors = {
            "idle": ("#5577aa", "#334466", "#223355", "#8899bb"),
            "thinking": ("#6699cc", "#4477aa", "#335588", "#aaccee"),
            "quiet": ("#334466", "#223355", "#112244", "#445577"),
            "active": ("#88bbee", "#6699cc", "#4477aa", "#ccddff"),
        }
        a, b, c, glow = colors.get(mood, colors["idle"])
        
        self.canvas.delete("orb_gradient")
        cx, cy = 100, 70
        r = 48 * self.breathe_scale
        
        # 光晕
        for i in range(6, 0, -1):
            rr = r + i * 8
            alpha_hex = f"{30 - i*4:02x}"
            color = f"#{glow[1:3]}{glow[3:5]}{glow[5:7]}{alpha_hex}"
            try:
                self.canvas.create_oval(cx-rr, cy-rr, cx+rr, cy+rr,
                                        fill=color, outline="", tags="orb_gradient")
            except:
                pass
        
        # 主体
        try:
            self.canvas.create_oval(cx-r, cy-r, cx+r, cy+r,
                                    fill=a, outline="", tags="orb_gradient")
            # 高光
            self.canvas.create_oval(cx-r*0.5, cy-r*0.6, cx+r*0.1, cy+r*0.1,
                                    fill="#aaccff", outline="", tags="orb_gradient")
        except:
            pass
    
    def update_particles(self):
        for i, p in enumerate(self.particles):
            dx = random.randint(-1, 1)
            dy = random.randint(-1, 1)
            self.canvas.move(p, dx, dy)
            
            coords = self.canvas.coords(p)
            if coords[0] < 20 or coords[0] > 180:
                self.canvas.move(p, -dx*2, 0)
            if coords[1] < 5 or coords[1] > 130:
                self.canvas.move(p, 0, -dy*2)
    
    def update_bubble(self, thought):
        if self.bubble_bg:
            self.canvas.delete(self.bubble_bg)
            self.bubble_bg = None
        
        if thought:
            # 气泡背景
            x1, y1, x2, y2 = 30, 162, 170, 200
            self.bubble_bg = self.canvas.create_rectangle(
                x1, y1, x2, y2, fill="#1a1a2e", outline="#334466", tags="bubble"
            )
            self.canvas.itemconfig(self.bubble_text, text=thought)
        else:
            self.canvas.itemconfig(self.bubble_text, text="")
    
    def update(self):
        self.phase += 0.05
        
        # 呼吸动画
        mood = self.state.get("mood", "idle")
        speeds = {"idle": 4, "thinking": 2, "quiet": 8, "active": 1.5}
        speed = speeds.get(mood, 4)
        self.breathe_scale = 1.0 + 0.05 * (1 if mood == "active" else 0.7) * \
                              (1 if mood == "quiet" else 1.5) * \
                              abs(__import__("math").sin(self.phase / speed))
        
        self.canvas.delete("orb_gradient")
        self.draw_orb(mood)
        self.update_particles()
        self.update_bubble(self.state.get("thought", ""))
        
        self.root.after(50, self.update)
    
    def check_state(self):
        try:
            with open(STATE_FILE, "r") as f:
                new_state = json.load(f)
                if new_state != self.state:
                    self.state = new_state
        except:
            pass
        self.root.after(3000, self.check_state)

if __name__ == "__main__":
    Avatar()
