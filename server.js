const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

// ===== 配置 =====
const PORT = 8080;
const TOOLS_DIR = path.join(__dirname, 'tools');
const META_FILE = path.join(__dirname, 'tools_meta.json');
// ===== 配置结束 =====

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.js':   'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.sh':   'text/plain; charset=utf-8',
  '.bat':  'text/plain; charset=utf-8',
  '.ps1':  'text/plain; charset=utf-8',
  '.py':   'text/plain; charset=utf-8',
  '.jar':  'application/java-archive',
  '.yml':  'text/plain; charset=utf-8',
  '.yaml': 'text/plain; charset=utf-8',
  '.xml':  'application/xml; charset=utf-8',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.ico':  'image/x-icon',
  '.zip':  'application/zip',
};

function getMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_TYPES[ext] || 'application/octet-stream';
}

// 读取工具元数据
function loadMeta() {
  try {
    const raw = fs.readFileSync(META_FILE, 'utf-8');
    return JSON.parse(raw);
  } catch (e) {
    return [];
  }
}

// 扫描目录补充未配置的文件
function scanDir() {
  const entries = [];
  try {
    const items = fs.readdirSync(TOOLS_DIR, { withFileTypes: true });
    for (const item of items) {
      entries.push({
        name: item.name,
        isDir: item.isDirectory(),
        path: path.join(TOOLS_DIR, item.name),
      });
    }
  } catch (e) {}
  return entries;
}

// 读取脚本文件前 N 行（用于预览）
function readPreview(filePath, maxLines = 30) {
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const lines = content.split('\n').slice(0, maxLines);
    return lines.join('\n');
  } catch (e) {
    return '';
  }
}

// 获取目录内文件列表
function listDirFiles(dirPath) {
  try {
    return fs.readdirSync(dirPath).filter(f => {
      const full = path.join(dirPath, f);
      return fs.statSync(full).isFile();
    });
  } catch (e) {
    return [];
  }
}

// 构建完整的工具列表（元数据 + 自动扫描补充）
function buildToolList() {
  const meta = loadMeta();
  const metaFiles = new Set(meta.map(m => m.file));
  const dirEntries = scanDir();

  // 补充未在 meta 中配置的文件
  for (const entry of dirEntries) {
    if (!metaFiles.has(entry.name)) {
      meta.push({
        id: entry.name.replace(/\.[^.]+$/, '').replace(/[^a-zA-Z0-9_]/g, '_'),
        name: entry.name,
        file: entry.name,
        isDir: entry.isDir,
        category: '未分类',
        tags: [entry.isDir ? '目录' : path.extname(entry.name).replace('.', '')],
        description: '',
        usage: '',
        platform: '未知',
        language: entry.isDir ? '多文件' : path.extname(entry.name).replace('.', ''),
        author: '',
      });
    }
  }

  // 补充文件大小和预览
  for (const tool of meta) {
    const toolPath = path.join(TOOLS_DIR, tool.file);
    try {
      if (tool.isDir) {
        tool.files = listDirFiles(toolPath);
        tool.size = tool.files.length + ' 个文件';
      } else {
        const stat = fs.statSync(toolPath);
        tool.size = stat.size < 1024 * 1024
          ? (stat.size / 1024).toFixed(1) + ' KB'
          : (stat.size / 1024 / 1024).toFixed(1) + ' MB';
        // 脚本类文件自动预览
        const ext = path.extname(tool.file).toLowerCase();
        if (['.sh', '.bat', '.ps1', '.py', '.js', '.yml', '.yaml'].includes(ext)) {
          tool.preview = readPreview(toolPath);
        }
      }
    } catch (e) {
      tool.size = '未知';
      tool.missing = true;
    }
  }

  return meta;
}

// 打包目录为 zip（简易实现，不用外部依赖）
function packDir(dirPath) {
  // 使用 Node 内置方式列出文件，前端逐个下载
  // 简化：直接让前端逐个下载目录内文件
  const files = listDirFiles(dirPath);
  return files;
}

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;

  // API: 获取工具列表
  if (pathname === '/api/tools') {
    const tools = buildToolList();
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(tools));
    return;
  }

  // API: 获取工具详情（预览内容）
  if (pathname.startsWith('/api/detail/')) {
    const toolId = pathname.replace('/api/detail/', '');
    const tools = buildToolList();
    const tool = tools.find(t => t.id === toolId);
    if (!tool) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    const toolPath = path.join(TOOLS_DIR, tool.file);
    try {
      if (tool.isDir) {
        tool.files = listDirFiles(toolPath);
        tool.dirFiles = {};
        for (const f of tool.files) {
          const fp = path.join(toolPath, f);
          const ext = path.extname(f).toLowerCase();
          if (['.sh', '.bat', '.ps1', '.py', '.js', '.json', '.yml', '.yaml', '.xml', '.log'].includes(ext)) {
            tool.dirFiles[f] = readPreview(fp, 50);
          }
        }
      } else {
        if (!tool.preview) {
          tool.preview = readPreview(toolPath, 50);
        }
      }
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(tool));
    } catch (e) {
      res.writeHead(500);
      res.end('Error reading tool');
    }
    return;
  }

  // API/下载：单个文件下载
  if (pathname.startsWith('/download/')) {
    const filePath = path.join(TOOLS_DIR, pathname.replace('/download/', ''));
    try {
      const stat = fs.statSync(filePath);
      if (stat.isDirectory()) {
        // 目录下载：返回文件列表，前端逐个下载
        const files = listDirFiles(filePath);
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ type: 'dir', files }));
        return;
      }
      res.writeHead(200, {
        'Content-Type': getMimeType(filePath),
        'Content-Disposition': 'attachment; filename="' + path.basename(filePath) + '"',
        'Content-Length': stat.size,
      });
      fs.createReadStream(filePath).pipe(res);
    } catch (e) {
      res.writeHead(404);
      res.end('File not found');
    }
    return;
  }

  // 静态文件：public 目录
  if (pathname === '/' || pathname === '/index.html') {
    const html = fs.readFileSync(path.join(__dirname, 'public', 'index.html'), 'utf-8');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  // 其他静态资源
  const staticPath = path.join(__dirname, 'public', pathname);
  try {
    const stat = fs.statSync(staticPath);
    if (stat.isFile()) {
      res.writeHead(200, { 'Content-Type': getMimeType(staticPath) });
      fs.createReadStream(staticPath).pipe(res);
      return;
    }
  } catch (e) {}

  res.writeHead(404);
  res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('========================================');
  console.log('  工具管理站已启动!');
  console.log('========================================');
  console.log(`  本机访问: http://localhost:${PORT}`);
  console.log(`  局域网访问: http://<你的IP>:${PORT}`);
  console.log(`  工具目录: ${TOOLS_DIR}`);
  console.log('');
  console.log('  按 Ctrl+C 停止服务');
  console.log('========================================');

  // 自动获取本机 IP
  try {
    const nets = require('os').networkInterfaces();
    for (const name of Object.keys(nets)) {
      for (const net of nets[name]) {
        if (net.family === 'IPv4' && !net.internal) {
          console.log(`  局域网地址: http://${net.address}:${PORT}`);
        }
      }
    }
  } catch (e) {}
});
