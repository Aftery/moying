/// 数据源「自建部署指南」文案常量（Markdown）
///
/// 面向「自定义书籍数据源」用户：引导其用 GitHub + Render 免费托管
/// simple-boot-douban-api（豆瓣图书代理），再把公网地址填进 App 的
/// 「Base URL」字段。
///
/// 文案与 UI 解耦 —— 改文案不必动 Widget。渲染见
/// `lib/widgets/data_source_guide_sheet.dart`（flutter_markdown，
/// 默认 GFM，支持标题 / 代码块 / 表格 / 引用；文内链接经 url_launcher
/// 交系统浏览器打开）。
library;

/// 指南正文（Markdown）。
///
/// 注意事项（改文案时请遵守）：
/// - **不要把代码块嵌进有序列表**：`1.` 项目里放 ``` 围栏容易被解析成
///   独立块、把列表拆断导致编号重排，故「替换 Dockerfile」一步改用
///   加粗小标题承载；
/// - 有序列表保持连续，中间不要插入表格（同理会拆断列表）。
const String kDataSourceDeployGuide = r'''
# 🚀 墨影图书服务（Douban API）自建部署指南

由于豆瓣接口限制，使用自建代理服务可确保图书检索的稳定与流畅。

你可以通过 **GitHub + Render** 提供的免费云服务，**无需信用卡、零成本、5 分钟**完成部署。

---

## 第一阶段：准备项目仓库

**① 登录并 Fork 项目仓库**

登录 GitHub，打开 [simple-boot-douban-api](https://github.com/jianyun8023/simple-boot-douban-api)，点击右上角的 **Fork**，把该仓库复制到你自己的账号下。

**② 替换 Dockerfile**

将仓库根目录下的 `Dockerfile` 内容整体替换为以下优化配置（解决免费服务器内存超限与编译问题）：

```dockerfile
# 编译打包阶段
FROM maven:3.8.8-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests -U -e

# 运行阶段
FROM eclipse-temurin:8-jre-alpine
WORKDIR /app
COPY --from=builder /build/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-Xms256m", "-Xmx384m", "-Djava.security.egd=file:/dev/./urandom", "-jar", "app.jar"]
```

**③ 提交修改**

提交（Commit）修改并保存。

---

## 第二阶段：在 Render 托管服务

1. 打开 [Render 官网](https://render.com)，并使用 GitHub 账号登录。
2. 点击 **New +** 按钮，选择 **Web Service**。
3. 在仓库列表中找到并连接（Connect）你刚才 Fork 的 `simple-boot-douban-api` 仓库。
4. 按下表填写基础参数，然后点击 **Create Web Service**，等待 2–3 分钟完成自动构建。

**基础参数**

| 参数 | 填写内容 |
| --- | --- |
| Name | 任意填写（如 `my-douban-api`） |
| Region | **Singapore**（新加坡，延迟较低） |
| Language | **Docker** |
| Instance Type | **Free（$0/month）** |

**（可选）配置豆瓣 Cookie 以提升防封能力**

展开 **Environment Variables**，添加如下变量：

| 变量名 | 值 |
| --- | --- |
| `COOKIE` | 你的豆瓣 Cookie |

---

## 第三阶段：获取并绑定到墨影 App

1. 构建成功后，页面左上角会显示绿色的 **Live** 标志。
2. 复制 Render 提供的公网域名地址（形如 `https://my-douban-api.onrender.com`）。
3. 打开 **墨影 App →「个人」→ 数据源管理 → 添加书籍数据源**，把该地址填入 **Base URL** 输入框即可。

---

> 💡 **贴心提示**
>
> Render 免费版服务在连续 **15 分钟**无请求后会自动休眠。休眠后的首次搜索需等待约 **30 秒**服务重新唤醒，之后即恢复极速体验。
>
> 建议搭配 [UptimeRobot](https://uptimerobot.com) 配置每 **10 分钟**一次的心跳 Ping，让服务保持常驻在线。
''';
