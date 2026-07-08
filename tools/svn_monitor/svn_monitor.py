#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN 代码提交监听器
每小时检查所有项目的 SVN 提交记录，仅通知上次检查后新增的提交。
"""

import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from datetime import datetime

# ============================================================
# 状态文件（追踪每个项目上次看到的版本号）
# ============================================================

def load_state(state_path):
    """读取状态文件，返回 {项目名: 最后版本号}"""
    if os.path.exists(state_path):
        with open(state_path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}

def save_state(state_path, state):
    """保存状态文件"""
    with open(state_path, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)

# ============================================================
# 配置加载
# ============================================================

def load_config(config_path):
    """读取 JSON 配置文件"""
    if not os.path.exists(config_path):
        # 在脚本同目录查找
        alt_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "svn_monitor_config.json")
        if os.path.exists(alt_path):
            return load_config(alt_path)
        print(f"[错误] 配置文件不存在: {config_path}")
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    # 校验必要字段
    required = ["svn_base_url", "projects"]
    for key in required:
        if key not in config:
            print(f"[错误] 配置文件缺少必要字段: {key}")
            sys.exit(1)

    return config


# ============================================================
# SVN 日志获取
# ============================================================

def get_svn_log(svn_url, username="", password="", today_str=None):
    """
    获取指定 SVN URL 的今日提交日志。
    返回 (project_name, [commit 信息列表])
    每项 commit 包含: revision, author, date, msg
    """
    if today_str is None:
        today_str = datetime.now().strftime("%Y-%m-%d")

    # 构建 svn log 命令
    # 使用 --xml 便于解析
    cmd = [
        "svn", "log", svn_url,
        "-r", f"{{{today_str}}}:HEAD",
        "--xml",
        "--non-interactive",
        "--trust-server-cert",
    ]
    if username:
        cmd += ["--username", username]
    if password:
        cmd += ["--password", password]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,  # 每项目最多等 60 秒
            creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
        )
    except subprocess.TimeoutExpired:
        return svn_url, None, "连接超时（超过60秒）"
    except FileNotFoundError:
        return svn_url, None, "SVN 命令行工具未找到，请确认已安装 TortoiseSVN 或 SVN CLI"

    if result.returncode != 0:
        stderr = result.stderr.strip() if result.stderr else "未知错误"
        return svn_url, None, f"SVN 命令执行失败: {stderr}"

    if not result.stdout or not result.stdout.strip():
        return svn_url, [], None  # 空仓库或无提交

    # 解析 XML 输出
    commits = []
    try:
        root = ET.fromstring(result.stdout)
        for logentry in root.findall("logentry"):
            revision = logentry.attrib.get("revision", "?")
            author = logentry.find("author")
            author = author.text if author is not None else "unknown"
            date_str = logentry.find("date")
            date_str = date_str.text if date_str is not None else ""

            # 提取日期部分 (YYYY-MM-DD)
            date_match = re.match(r"(\d{4}-\d{2}-\d{2})", date_str)
            commit_date = date_match.group(1) if date_match else ""

            # 只保留今天的提交
            if commit_date != today_str:
                continue

            msg = logentry.find("msg")
            msg = msg.text.strip() if msg is not None and msg.text else "(无提交说明)"

            commits.append({
                "revision": revision,
                "author": author,
                "date": date_str,
                "msg": msg,
            })
    except ET.ParseError as e:
        return svn_url, None, f"XML 解析失败: {e}"

    return svn_url, commits, None


# ============================================================
# Windows 通知
# ============================================================

def show_notification(title, message):
    """
    弹出 Windows 弹窗通知，使用 tkinter 自定义大字体窗口。
    如果标题为空或无效，静默跳过。
    """
    if not title or not message:
        return

    try:
        import tkinter as tk
        from tkinter import ttk, font
    except ImportError:
        # tkinter 不可用，回退控制台输出
        print(f"\n{'='*60}")
        print(f"  {title}")
        print(f"  {message}")
        print(f"{'='*60}\n")
        return

    # 创建顶级窗口
    root = tk.Tk()
    root.title(title)

    # 设置字体 —— 大字号
    title_font = font.Font(family="Microsoft YaHei", size=15, weight="bold")
    body_font = font.Font(family="Microsoft YaHei", size=13)

    # 窗口始终置顶
    root.attributes("-topmost", True)
    root.lift()
    root.focus_force()

    # 获取屏幕尺寸，窗口最大不超过屏幕 80%
    screen_w = root.winfo_screenwidth()
    screen_h = root.winfo_screenheight()
    max_w = int(screen_w * 0.75)
    max_h = int(screen_h * 0.75)

    # 主容器
    main_frame = ttk.Frame(root, padding=16)
    main_frame.pack(fill="both", expand=True)

    # 标题栏
    title_label = ttk.Label(main_frame, text=title, font=title_font, wraplength=max_w - 60)
    title_label.pack(anchor="w", pady=(0, 8))

    # 分隔线
    ttk.Separator(main_frame, orient="horizontal").pack(fill="x", pady=(0, 8))

    # 消息体 - 可滚动文本
    text_frame = ttk.Frame(main_frame)
    text_frame.pack(fill="both", expand=True)

    text_widget = tk.Text(
        text_frame,
        font=body_font,
        wrap="word",
        borderwidth=0,
        padx=8,
        pady=8,
        relief="flat",
        bg="#f8f8f8",
        fg="#222222",
        spacing2=4,       # 行间距
        spacing1=2,
    )
    text_widget.insert("1.0", message)
    text_widget.configure(state="disabled")  # 只读

    scrollbar = ttk.Scrollbar(text_frame, command=text_widget.yview)
    text_widget.configure(yscrollcommand=scrollbar.set)

    text_widget.pack(side="left", fill="both", expand=True)
    scrollbar.pack(side="right", fill="y")

    # 关闭按钮
    btn_frame = ttk.Frame(main_frame)
    btn_frame.pack(fill="x", pady=(12, 0))

    close_btn = ttk.Button(
        btn_frame,
        text="关闭",
        command=root.destroy,
        width=12,
    )
    close_btn.pack(side="right")

    # 绑定 ESC 键关闭
    root.bind("<Escape>", lambda e: root.destroy())

    # 先初始显示以计算实际内容尺寸
    root.update_idletasks()

    # 根据内容自适应尺寸，不超过最大限制
    req_w = text_widget.winfo_reqwidth() + 100
    req_h = text_widget.winfo_reqheight() + 160

    win_w = min(req_w, max_w)
    win_h = min(req_h, max_h)

    # 居中放置
    x = (screen_w - win_w) // 2
    y = (screen_h - win_h) // 2
    root.geometry(f"{win_w}x{win_h}+{x}+{y}")

    # 设置最小尺寸
    root.minsize(420, 280)

    root.mainloop()


def show_small_notification(title, message):
    """
    弹出一个小巧的提示窗口（用于"暂无更新"等中性信息）。
    """
    if not title or not message:
        return

    try:
        import tkinter as tk
        from tkinter import ttk, font
    except ImportError:
        return

    root = tk.Tk()
    root.title(title)
    root.attributes("-topmost", True)
    root.resizable(False, False)

    body_font = font.Font(family="Microsoft YaHei", size=11)

    # 获取屏幕尺寸
    screen_w = root.winfo_screenwidth()
    screen_h = root.winfo_screenheight()

    # 紧凑布局
    main_frame = ttk.Frame(root, padding=(20, 14))
    main_frame.pack()

    ttk.Label(main_frame, text=message, font=body_font).pack()

    btn_frame = ttk.Frame(main_frame)
    btn_frame.pack(pady=(10, 0))
    ttk.Button(btn_frame, text="确定", command=root.destroy, width=8).pack()

    root.bind("<Escape>", lambda e: root.destroy())
    root.update_idletasks()

    win_w = root.winfo_reqwidth()
    win_h = root.winfo_reqheight()
    x = (screen_w - win_w) // 2
    y = (screen_h - win_h) // 2
    root.geometry(f"+{x}+{y}")

    root.mainloop()


# ============================================================
# 主逻辑
# ============================================================

def main():
    # 获取脚本所在目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_path = os.environ.get("SVN_MONITOR_CONFIG", os.path.join(script_dir, "svn_monitor_config.json"))
    state_path = os.path.join(script_dir, "svn_monitor_state.json")

    # 加载配置
    config = load_config(config_path)
    svn_base = config["svn_base_url"].rstrip("/")
    projects = config["projects"]
    username = config.get("svn_username", "")
    password = config.get("svn_password", "")

    # 加载上次状态（记录每个项目最后看到的版本号）
    last_state = load_state(state_path)
    new_state = {}  # 本次运行后的新状态

    today_str = datetime.now().strftime("%Y-%m-%d")
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 开始检查 {len(projects)} 个项目...")

    changed_projects = []  # [(项目名, 提交数, [提交详情])]
    error_projects = []    # [(项目名, 错误信息)]

    for project in projects:
        svn_url = f"{svn_base}/{project}"
        print(f"  ...检查 {project}: {svn_url}")

        _, all_commits, error = get_svn_log(svn_url, username, password, today_str)

        if error:
            error_projects.append((project, error))
            # 出错时保留旧状态
            if project in last_state:
                new_state[project] = last_state[project]
            print(f"    [错误] {project}: {error}")
            continue

        # 记录最新的版本号
        max_rev = 0
        for c in all_commits:
            rev = int(c["revision"])
            if rev > max_rev:
                max_rev = rev

        if max_rev > 0:
            new_state[project] = max_rev
        elif project in last_state:
            new_state[project] = last_state[project]

        # 筛选出上次检查之后新增的提交
        last_rev = last_state.get(project, 0)
        new_commits = [c for c in all_commits if int(c["revision"]) > last_rev]

        if new_commits:
            changed_projects.append((project, len(new_commits), new_commits))
            print(f"    [新增变动] {project}: {len(new_commits)} 次提交")
            for c in new_commits:
                print(f"      r{c['revision']} by {c['author']}: {c['msg'][:60]}")
        elif all_commits:
            print(f"    [无新增] {project}（今日 {len(all_commits)} 次，已通知过）")
        else:
            print(f"    [无变动] {project}")

    # 先保存状态，再弹窗（弹窗是阻塞的，状态必须先落盘）
    save_state(state_path, new_state)

    # 显示通知（所有信息汇总到一个弹窗）
    if changed_projects:
        lines = []
        for proj_name, count, commits in changed_projects:
            lines.append(f"【{proj_name}】 {count} 次提交:")
            for c in commits:
                lines.append(f"  r{c['revision']} - {c['author']}: {c['msg'][:60]}")
            lines.append("")

        project_names = "、".join([p[0] for p in changed_projects])
        total_commits = sum(p[1] for p in changed_projects)
        detail_text = "\n".join(lines)

        message = (
            f"以下项目有新增代码版本变动，请留意：\n\n"
            f"{project_names}\n"
            f"共 {total_commits} 次新提交\n\n"
            f"--- 详细 ---\n"
            f"{detail_text}"
        )

        show_notification(f"SVN 新增变动提醒 - {total_commits} 次提交", message)

    elif error_projects:
        # 只有出错没有变动时才弹错误窗口
        err_names = "、".join([e[0] for e in error_projects])
        show_notification(
            "SVN 监听错误",
            f"以下项目检查失败，请检查配置或网络：\n{err_names}"
        )
    else:
        # 无变动也无错误 —— 弹小窗告知暂无更新
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        show_small_notification(
            "SVN 监听",
            f"检查时间：{now_str}\n已检查 {len(projects)} 个项目，暂无代码更新"
        )

    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 检查完成。"
          f" 新增变动: {len(changed_projects)} 个项目，错误: {len(error_projects)} 个项目")


if __name__ == "__main__":
    main()
