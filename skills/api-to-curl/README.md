# ApiToCurl

从项目源码提取接口定义（路由、方法、路径、入参），生成可直接导入 Apifox/Postman 的 cURL 命令。支持 Go / Node.js / Java / Python / PHP 等多语言框架。

## 快速开始

```
curl-scan                     # 扫描项目，定位路由注册、host/port、全局前缀
curl-gen "创建用户"            # 针对指定接口生成 cURL
curl-batch "用户管理"          # 批量生成某模块/控制器的全部 cURL
curl-export                   # 输出可导入 Apifox 的格式
```

工作流程：`curl-scan`（首次/换项目时）→ `curl-gen` 或 `curl-batch` → `curl-export`。

## 子命令（4 个）

| 子命令 | 功能 | 说明 |
|--------|------|------|
| `curl-scan` | 扫描项目基础信息 | 技术栈、host:port、路由前缀、参数绑定风格 |
| `curl-gen` | 生成单个 cURL | 定位路由→提取参数→生成 cURL + 字段表 |
| `curl-batch` | 批量生成 cURL | 按模块/控制器/路由前缀批量处理 |
| `curl-export` | 导出 Apifox 格式 | cURL 清单 或 OpenAPI 3.0 JSON |

## 核心特性

- **多框架适配**：自动识别 Go (gin/echo/fiber)、Node.js (express/koa/nestjs)、Java (Spring Boot)、Python (Flask/Django/FastAPI)、PHP (Laravel) 等
- **语义化示例值**：phone→手机号、date→日期格式、id→非零整数，必填字段给非零值
- **信息来源可追溯**：每个接口标注路由注册位置和参数定义来源（文件名:行号）
- **不杜撰字段**：参数定义里没有的字段不出现在 cURL 中

## 技能内部结构

```
skills/api-to-curl/
├── SKILL.md                    # 主技能定义 + 子命令详细规则
└── README.md                   # 本文件
```

## 通用规则

- 字段名取序列化名称（json/form tag），非源码变量名
- 必填字段非零值，避免框架验证器判空报错
- 路由表找不到的接口不生成，不臆造
- 无法确认的 host/port 用占位标注，提示用户补全
