class AiVendor {
  const AiVendor(this.id, this.name, this.baseUrl);
  final String id;
  final String name;
  final String baseUrl;
}

const aiVendors = [
  AiVendor('openai', 'OpenAI', 'https://api.openai.com/v1'),
  AiVendor('deepseek', 'DeepSeek', 'https://api.deepseek.com'),
  AiVendor('kimi', 'Kimi', 'https://api.moonshot.cn/v1'),
  AiVendor(
    'qwen',
    '通义千问 · 中国内地',
    'https://dashscope.aliyuncs.com/compatible-mode/v1',
  ),
  AiVendor(
    'qwen-intl',
    '通义千问 · 国际',
    'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ),
  AiVendor('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1'),
  AiVendor('custom', '自定义兼容服务', ''),
];
