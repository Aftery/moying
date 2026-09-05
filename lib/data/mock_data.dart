import '../models/actor.dart';
import '../models/book.dart';
import '../models/movie.dart';

/// 完整书库（图书模块数据源，12 本）
///
/// 覆盖多种形态：在读/读完/想读、不同分类、不同进度、带/不带评分与感悟，
/// 便于列表筛选、详情与编辑页的交互演示。
/// 注：非 const —— [DateTime] 构造函数无常量求值；书籍均回填
/// createdAt（添加时间）/ startedAt（开始阅读）/ finishedAt（完成）合理日期。
final List<Book> kAllBooks = [
  // ---- 在读（含进度与中途评分）----
  Book(
    id: 'b1',
    title: '沙丘',
    author: '弗兰克·赫伯特',
    totalPages: 688,
    currentPage: 447,
    createdAt: DateTime(2025, 11, 2),
    startedAt: DateTime(2026, 2, 15),
    status: BookStatus.reading,
    rating: 4.6,
    year: 1965,
    coverHue: 258,
    emoji: '🏜️',
    category: '科幻',
    notes: '香料、沙虫与帝国博弈——厄拉科斯上的每一页都滚烫。目前读到「皇帝驾临」，政治张力彻底拉满。',
    description:
        '在寸草不生的沙漠星球厄拉科斯，少年保罗随家族接管香料开采权，却在帝国阴谋与资源争夺中被推上命运的风口浪尖——一场关于权力、宗教与生存的史诗就此展开。',
  ),
  Book(
    id: 'b2',
    title: '人类群星闪耀时',
    author: '斯蒂芬·茨威格',
    totalPages: 392,
    currentPage: 321,
    createdAt: DateTime(2025, 8, 14),
    startedAt: DateTime(2026, 6, 20),
    status: BookStatus.reading,
    rating: 4.5,
    year: 1927,
    coverHue: 205,
    emoji: '✨',
    category: '历史',
    notes: '茨威格写「决定世界命运的瞬间」，拜占庭陷落那一篇尤其震撼，历史的偶然被写得惊心动魄。',
    description:
        '茨威格以诗人之笔捕捉十四个改写人类历史的瞬间：拜占庭的陷落、亨德尔的复活、滑铁卢的一分钟……历史的必然与偶然，在电光石火间定格。',
  ),
  Book(
    id: 'b3',
    title: '三体Ⅱ：黑暗森林',
    author: '刘慈欣',
    totalPages: 470,
    currentPage: 145,
    createdAt: DateTime(2025, 6, 30),
    startedAt: DateTime(2026, 8, 28),
    status: BookStatus.reading,
    coverHue: 210,
    emoji: '🚀',
    category: '科幻',
    notes: '面壁计划徐徐展开，罗辑的成长线比想象中更耐读。',
    description:
        '三体舰队入侵在即，人类启动面壁计划迎战。在宇宙社会学两大公理构筑的猜疑链下，罗辑以一己之力，向整个宇宙喊出黑暗森林法则的真相。',
  ),

  // ---- 读完（带评分与感悟）----
  Book(
    id: 'b4',
    title: '1984',
    author: '乔治·奥威尔',
    totalPages: 328,
    currentPage: 328,
    createdAt: DateTime(2025, 1, 12),
    startedAt: DateTime(2025, 9, 3),
    finishedAt: DateTime(2025, 10, 18),
    status: BookStatus.finished,
    rating: 4.8,
    year: 1949,
    coverHue: 350,
    emoji: '👁️',
    category: '反乌托邦',
    notes: '老大哥在看着你。「战争即和平，自由即奴役，无知即力量。」读完脊背发凉，但值得每个时代重读。',
    description:
        '在极权统治的「大洋国」，温斯顿于思想警察的监视下偷偷书写日记，试图反抗被彻底剥夺的真相与自由——直到「友爱部」的房门为他打开。',
  ),
  Book(
    id: 'b5',
    title: '百年孤独',
    author: '加西亚·马尔克斯',
    totalPages: 360,
    currentPage: 360,
    createdAt: DateTime(2025, 3, 5),
    startedAt: DateTime(2026, 1, 4),
    finishedAt: DateTime(2026, 2, 14),
    status: BookStatus.finished,
    rating: 4.6,
    year: 1967,
    coverHue: 25,
    emoji: '🌀',
    category: '魔幻现实主义',
    notes: '布恩迪亚家族七代人的百年轮回。人名是难点，但越读越上头，魔幻与现实的边界模糊成诗。',
    description: '布恩迪亚家族七代人的兴衰在马孔多小镇循环上演：战争、情欲、预言与遗忘。魔幻与现实交织，勾勒出拉丁美洲一个世纪的孤独图景。',
  ),
  Book(
    id: 'b6',
    title: '三体',
    author: '刘慈欣',
    totalPages: 302,
    currentPage: 302,
    createdAt: DateTime(2025, 5, 18),
    startedAt: DateTime(2026, 3, 21),
    finishedAt: DateTime(2026, 4, 9),
    status: BookStatus.finished,
    rating: 4.9,
    year: 2008,
    coverHue: 190,
    emoji: '🌌',
    category: '科幻',
    notes: '「不要回答！不要回答！」三部曲的开端，黑暗森林理论的伏笔从这一部就开始埋下。',
    description:
        '天文学家叶文洁向宇宙发出地球的第一次啼鸣，四光年外的三体文明随即锁死人类基础科学。人类第一次意识到：在这片黑暗森林里，暴露即毁灭。',
  ),
  Book(
    id: 'b7',
    title: '月亮与六便士',
    author: '毛姆',
    totalPages: 275,
    currentPage: 275,
    createdAt: DateTime(2025, 4, 2),
    startedAt: DateTime(2026, 2, 20),
    finishedAt: DateTime(2026, 3, 6),
    status: BookStatus.finished,
    rating: 4.4,
    year: 1919,
    coverHue: 45,
    emoji: '🌙',
    category: '经典',
    notes: '满地都是六便士，他却抬头看见了月亮。理想主义者的极端样本，读完久久不能平静。',
    description:
        '伦敦证券经纪人思特里克兰德人到中年抛下一切远走巴黎与塔希提，只为追逐绘画的梦。满地六便士与天上月亮之间，他义无反顾选择了后者。',
  ),
  Book(
    id: 'b8',
    title: '小王子',
    author: '安托万·德·圣-埃克苏佩里',
    totalPages: 96,
    currentPage: 96,
    createdAt: DateTime(2025, 6, 12),
    startedAt: DateTime(2026, 5, 1),
    finishedAt: DateTime(2026, 5, 3),
    status: BookStatus.finished,
    rating: 4.7,
    year: 1943,
    coverHue: 350,
    emoji: '🌹',
    category: '经典',
    notes: '「真正重要的东西，用眼睛是看不见的。」每次重读都有新的温柔与怅惘。',
    description: '飞行员在撒哈拉沙漠遇见来自 B-612 星球的小王子。玫瑰、狐狸与浩瀚星空教会他：真正重要的东西，用眼睛是看不见的。',
  ),
  Book(
    id: 'b9',
    title: '你当像鸟飞往你的山',
    author: '塔拉·韦斯特弗',
    totalPages: 388,
    currentPage: 388,
    createdAt: DateTime(2025, 9, 21),
    startedAt: DateTime(2026, 4, 25),
    finishedAt: DateTime(2026, 6, 30),
    status: BookStatus.finished,
    rating: 4.9,
    year: 2018,
    coverHue: 95,
    emoji: '🦅',
    category: '传记',
    notes: '教育如何重塑一个人的一生。读的过程中数次合上书深呼吸，关于家庭与自我的拉扯写得极为诚实。',
    description: '生长于极端摩门教家庭的女孩塔拉，十七岁前没上过学，却凭借自学考入剑桥。在逃离与回归之间，她用教育亲手重塑了自己的一生。',
  ),

  // ---- 想读（未开始，无评分）----
  Book(
    id: 'b10',
    title: '克拉拉与太阳',
    author: '石黑一雄',
    totalPages: 350,
    currentPage: 0,
    createdAt: DateTime(2026, 8, 20),
    status: BookStatus.planToRead,
    year: 2021,
    coverHue: 285,
    emoji: '☀️',
    category: '文学',
    description:
        '专为陪伴儿童而生的太阳能人工智能克拉拉，被女孩乔西带回温暖的家。透过她精准又天真的目光，石黑一雄温柔追问：爱，究竟能否被复制？',
  ),
  Book(
    id: 'b11',
    title: '人类简史',
    author: '尤瓦尔·赫拉利',
    totalPages: 440,
    currentPage: 0,
    createdAt: DateTime(2026, 7, 10),
    status: BookStatus.planToRead,
    year: 2011,
    coverHue: 160,
    emoji: '🌍',
    category: '历史',
    description:
        '从认知革命、农业革命到科学革命，赫拉利以十万年尺度重述人类史：智人如何凭虚构故事登上食物链顶端，又将被自己创造的力量带向何方。',
  ),
  Book(
    id: 'b12',
    title: '嫌疑人X的献身',
    author: '东野圭吾',
    totalPages: 356,
    currentPage: 0,
    createdAt: DateTime(2026, 8, 30),
    status: BookStatus.planToRead,
    year: 2005,
    coverHue: 280,
    emoji: '🎭',
    category: '悬疑',
    description: '天才数学家石神为守护心仪之人，布下一道近乎完美的数学谜题。当物理学家汤川识破真相，谜底背后，是令人窒息的献身与孤独。',
  ),
];

/// 电影列表（电影库完整数据源，10 部）
///
/// 覆盖多种形态：已评分/已看/想看、不同类型组合、带/不带影评与演员，
/// 便于列表筛选、详情与编辑页的交互演示。
/// 注：非 const —— [DateTime] 构造函数无常量求值。
final List<Movie> kMovieList = [
  // 「想看」入库（原本仅用于仪表盘演示集的 kUpcomingMovies 并入）
  const Movie(
    id: 'm1',
    title: '奥本海默',
    year: 2023,
    englishTitle: 'Oppenheimer',
    director: '克里斯托弗·诺兰',
    status: MovieStatus.watchlist,
    coverHue: 32,
    emoji: '☢️',
  ),
  const Movie(
    id: 'm2',
    title: '沙丘 2',
    year: 2024,
    englishTitle: 'Dune: Part Two',
    director: '德尼·维尔纳夫',
    status: MovieStatus.watchlist,
    coverHue: 258,
    emoji: '🐛',
  ),
  Movie(
    id: 'm3',
    title: '星际穿越',
    year: 2014,
    englishTitle: 'Interstellar',
    director: '克里斯托弗·诺兰',
    status: MovieStatus.rated,
    rating: 4.9,
    coverHue: 215,
    emoji: '🌌',
    releaseDate: DateTime(2014, 11, 7),
    watchDate: DateTime(2023, 11, 5),
    duration: 169,
    genres: ['科幻', '冒险', '悬疑'],
    description:
        '近未来的地球黄沙遍野，农作物相继枯萎，人类文明危在旦夕。前 NASA 宇航员库珀在神秘虫洞指引下，与队友穿越星际寻找人类的新家园——这场以「爱」为终极维度的父女远征，将时间膨胀、引力方程与第五维度写成最浪漫的宇宙诗篇。',
    review:
        '第一次在影院看哭的太空片。黑洞「卡冈图雅」的视觉奇观至今无人超越，「不要温和地走进那个良夜」的吟诵与幽灵书架回旋曲在脑中轰鸣。诺兰把硬科幻拍出了神性与人性，五星当之无愧。',
    actorIds: ['马修·麦康纳', '安妮·海瑟薇', '杰西卡·查斯坦', '迈克尔·凯恩'],
  ),
  Movie(
    id: 'm4',
    title: '盗梦空间',
    year: 2010,
    englishTitle: 'Inception',
    director: '克里斯托弗·诺兰',
    status: MovieStatus.rated,
    rating: 4.8,
    coverHue: 258,
    emoji: '🌀',
    releaseDate: DateTime(2010, 9, 1),
    watchDate: DateTime(2020, 3, 14),
    duration: 148,
    genres: ['科幻', '悬疑', '动作'],
    description:
        '造梦师柯布带领团队潜入他人梦境深处窃取机密，这一次任务却是在目标脑海中植入一个「想法」。随着梦境层级层层深入，现实与梦境的边界开始崩塌——当图腾还在旋转，谁又能确定自己醒着？',
    review:
        '层层嵌套的梦境结构在第二遍才真正看透。诺兰用蒙太奇把「潜意识」拍成了可触摸的城市折叠与失重走廊，最后陀螺停没停成了影史最著名的开放谜题。',
    actorIds: ['莱昂纳多·迪卡普里奥', '约瑟夫·高登-莱维特', '艾伦·佩吉', '汤姆·哈迪'],
  ),
  Movie(
    id: 'm5',
    title: '楚门的世界',
    year: 1998,
    englishTitle: 'The Truman Show',
    director: '彼得·威尔',
    status: MovieStatus.rated,
    rating: 4.6,
    coverHue: 175,
    emoji: '📺',
    releaseDate: DateTime(1998, 6, 5),
    watchDate: DateTime(2021, 8, 21),
    duration: 103,
    genres: ['剧情', '科幻'],
    description:
        '三十岁的保险经纪楚门住在完美的海景小镇，生活美满得如同广告片——直到他发现天空的吊灯、从不回头的路人、和一辆永远在兜圈的汽车。原来他的一生都是一场全球直播的真人秀，而他，是唯一不知情的演员。',
    review:
        '「如果再也不能见到你，祝你早安、午安、晚安。」第一次看是奇幻寓言，多年后重看成为每个人的自省镜：我们又何尝不是在既定的剧本里寻找那扇通往真实世界的门？',
    actorIds: ['金·凯瑞', '劳拉·琳妮', '艾德·哈里斯'],
  ),
  Movie(
    id: 'm6',
    title: '阿甘正传',
    year: 1994,
    englishTitle: 'Forrest Gump',
    director: '罗伯特·泽米吉斯',
    status: MovieStatus.watched,
    rating: 4.7,
    coverHue: 30,
    emoji: '🪶',
    releaseDate: DateTime(1994, 7, 6),
    watchDate: DateTime(2022, 2, 12),
    duration: 142,
    genres: ['剧情', '爱情'],
    description:
        '智商只有 75 的阿甘凭借一颗纯粹的心，从阿拉巴马的乡村跑进大学橄榄球场，跑进越战丛林，跑向乒乓外交与虾船生意，一路见证并参与美国几十年的历史变迁。人生就像一盒巧克力，你永远不知道下一颗是什么味道。',
    review:
        '把「傻人有傻福」讲成了最温柔的时代史诗。羽毛飘起又落下，阿甘始终在奔跑——珍妮那句「跑，福雷斯特，跑！」大概是对自由最朴素的定义。',
    actorIds: ['汤姆·汉克斯', '罗宾·怀特', '加里·西尼斯'],
  ),
  Movie(
    id: 'm7',
    title: '银翼杀手 2049',
    year: 2017,
    englishTitle: 'Blade Runner 2049',
    director: '德尼·维尔纳夫',
    status: MovieStatus.watchlist,
    coverHue: 320,
    emoji: '🌧️',
    releaseDate: DateTime(2017, 10, 6),
    duration: 164,
    genres: ['科幻', '悬疑', '剧情'],
    description:
        '复制人执行官 K 在追查旧型号复制人的过程中，发现了一个被掩埋三十年的秘密——足以颠覆人类与复制人秩序的阶级真相。在霓虹与粉尘共舞的废土都市里，K 开始追问一个连人类都在回避的问题：我，是谁？',
    actorIds: ['瑞恩·高斯林', '哈里森·福特', '安娜·德·阿玛斯'],
  ),
  Movie(
    id: 'm8',
    title: '千与千寻',
    year: 2001,
    englishTitle: 'Spirited Away',
    director: '宫崎骏',
    status: MovieStatus.rated,
    rating: 4.9,
    coverHue: 5,
    emoji: '⛩️',
    releaseDate: DateTime(2001, 7, 20),
    watchDate: DateTime(2019, 6, 21),
    duration: 125,
    genres: ['动画', '奇幻', '冒险'],
    description:
        '十岁少女千寻随父母误入神灵世界，父母因贪食变成猪，千寻被迫留在油屋为汤婆婆打工。在名字被夺走的国度里，她遇见了无脸男、白龙与锅炉爷爷——用纯真与勇气，一点点找回自己的名字和回家的路。',
    review:
        '宫崎骏献给孩子的成长童话，成年人却能看哭。名字、贪婪、欲望与救赎——「不要忘记你的名字」大概是提醒我们每个人：无论走多远，都别忘了自己是谁。',
    actorIds: ['柊瑠美', '入野自由', '夏木真理'],
  ),
];

/// 演员实体 seed 集合（actors.json 首启数据）
///
/// 由电影 [kMovieList] 的 actorIds 直接派生：seed 演员采用 **id = name** 策略，
/// 保证引用完整性由构造方式成立（每个 actorId 必有同名演员），且现有电影
/// 详情页按 actorIds 直接渲染的展示逻辑零改动。后续编辑页新建的演员
/// 由 id 生成器生成（`a_` + 微秒时间戳），与 seed 演员共存无冲突。
final List<Actor> kActors = kMovieList
    .expand((m) => m.actorIds ?? const <String>[])
    .toSet()
    .map((name) => Actor(id: name, name: name, createdAt: DateTime(2026, 1, 1)))
    .toList();
