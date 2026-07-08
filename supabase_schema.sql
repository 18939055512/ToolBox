-- ============================================
-- 工具管理站 - Supabase 数据库初始化
-- 在 Supabase 控制台 → SQL Editor 里执行这段
-- ============================================

-- 1. 创建工具元数据表
CREATE TABLE IF NOT EXISTS tools (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  category TEXT DEFAULT '未分类',
  tags TEXT[] DEFAULT '{}',          -- PostgreSQL 数组类型
  usage TEXT DEFAULT '',
  platform TEXT DEFAULT '未知',
  language TEXT DEFAULT '',
  author TEXT DEFAULT '',
  file_name TEXT NOT NULL,           -- 存储桶中的文件名
  is_dir BOOLEAN DEFAULT FALSE,      -- 是否是目录型工具
  dir_files TEXT[] DEFAULT '{}',     -- 目录下的文件列表
  file_size TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 启用 RLS（行级安全策略）
ALTER TABLE tools ENABLE ROW LEVEL SECURITY;

-- 3. 允许所有人读取（公开访问）
CREATE POLICY "公开读取工具列表"
  ON tools FOR SELECT
  USING (true);

-- 4. 允许所有人插入/更新/删除（简易版，后续可加管理员验证）
CREATE POLICY "允许管理工具"
  ON tools FOR ALL
  USING (true)
  WITH CHECK (true);

-- 5. 创建存储桶（用于存放工具文件）
-- 注意：存储桶需要在 Supabase 控制台 → Storage 里手动创建
-- 桶名：tool-files
-- 设置为公开桶（Public bucket），这样文件可以直接通过 URL 下载

-- 6. 插入初始数据（已有的3个工具）
INSERT INTO tools (id, name, description, category, tags, usage, platform, language, author, file_name, is_dir, dir_files, file_size) VALUES
('deploy', '通用一键部署脚本', '通用版一键部署脚本，备份→替换→重启→验证→日志。支持多服务切换，加新项目只需在 SERVICES 数组加一行配置。', '部署',
 ARRAY['部署','Java','重启','备份'], 'sh deploy.sh <服务名> [--skip-confirm] [--no-log] [--jar-path PATH]',
 'Linux', 'Shell', 'wzb', 'deploy.sh', FALSE, ARRAY[]::TEXT[], '5.6 KB'),

('deploy_gcdw', 'gcdw专用部署脚本', 'gcdw 服务专用一键部署脚本，自动备份当前jar、替换新包、sudo重启、验证进程、跟踪日志。', '部署',
 ARRAY['部署','gcdw','重启','备份'], 'sh deploy_gcdw.sh [--skip-confirm] [--no-log]',
 'Linux', 'Shell', 'wzb', 'deploy_gcdw.sh', FALSE, ARRAY[]::TEXT[], '5.0 KB'),

('svn_monitor', 'SVN代码监听器', 'Windows SVN 提交监听工具，每小时自动扫描所有 SVN 项目，有新提交时弹窗通知。支持44个项目，零外部依赖。', '监控',
 ARRAY['SVN','监控','通知','Windows'], '运行 install.bat 安装，自动创建计划任务每小时运行',
 'Windows', 'Python', 'wzb', 'svn_monitor', TRUE, ARRAY['install.bat','run_monitor.bat','setup_task.ps1','svn_monitor.py','svn_monitor_config.json','svn_monitor_state.json'], '7 个文件')
ON CONFLICT (id) DO NOTHING;
