#!/usr/bin/env python3
"""
测试 NotebookLM API 服务器

用法:
    python test_api.py [--host HOST] [--port PORT] [--api-key KEY]
"""

import argparse
import json
import sys

try:
    import httpx
except ImportError:
    print("错误: 需要安装 httpx")
    print("运行: pip install httpx")
    sys.exit(1)


def test_health(base_url: str):
    """测试健康检查端点"""
    print("🏥 测试健康检查...")
    try:
        response = httpx.get(f"{base_url}/health", timeout=10.0)
        response.raise_for_status()
        print(f"✅ 健康检查通过: {response.json()}")
        return True
    except Exception as e:
        print(f"❌ 健康检查失败: {e}")
        return False


def test_models(base_url: str, api_key: str = None):
    """测试模型列表端点"""
    print("\n📋 测试模型列表...")
    headers = {}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    
    try:
        response = httpx.get(f"{base_url}/v1/models", headers=headers, timeout=10.0)
        response.raise_for_status()
        data = response.json()
        print(f"✅ 模型列表: {json.dumps(data, indent=2, ensure_ascii=False)}")
        return True
    except Exception as e:
        print(f"❌ 模型列表失败: {e}")
        return False


def test_chat_completion(base_url: str, api_key: str = None, notebook_id: str = None):
    """测试聊天完成端点"""
    print("\n💬 测试聊天完成...")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    
    payload = {
        "model": "notebooklm",
        "messages": [
            {"role": "user", "content": "Hello, this is a test message."}
        ]
    }
    
    if notebook_id:
        payload["notebook_id"] = notebook_id
    
    try:
        response = httpx.post(
            f"{base_url}/v1/chat/completions",
            headers=headers,
            json=payload,
            timeout=30.0
        )
        response.raise_for_status()
        data = response.json()
        
        if "choices" in data and len(data["choices"]) > 0:
            message = data["choices"][0]["message"]["content"]
            print(f"✅ 聊天完成成功")
            print(f"📝 响应: {message[:200]}...")
            return True
        else:
            print(f"⚠️  响应格式异常: {json.dumps(data, indent=2, ensure_ascii=False)}")
            return False
    except httpx.HTTPStatusError as e:
        print(f"❌ 聊天完成失败 (HTTP {e.response.status_code})")
        try:
            error_data = e.response.json()
            print(f"错误详情: {json.dumps(error_data, indent=2, ensure_ascii=False)}")
        except:
            print(f"错误详情: {e.response.text}")
        return False
    except Exception as e:
        print(f"❌ 聊天完成失败: {e}")
        return False


def test_streaming(base_url: str, api_key: str = None, notebook_id: str = None):
    """测试流式响应"""
    print("\n🌊 测试流式响应...")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    
    payload = {
        "model": "notebooklm",
        "messages": [
            {"role": "user", "content": "Hello, this is a streaming test."}
        ],
        "stream": True
    }
    
    if notebook_id:
        payload["notebook_id"] = notebook_id
    
    try:
        with httpx.stream(
            "POST",
            f"{base_url}/v1/chat/completions",
            headers=headers,
            json=payload,
            timeout=30.0
        ) as response:
            response.raise_for_status()
            
            chunks = []
            for line in response.iter_lines():
                if line.startswith("data: "):
                    data_str = line[6:]
                    if data_str == "[DONE]":
                        break
                    try:
                        chunk_data = json.loads(data_str)
                        if "choices" in chunk_data and len(chunk_data["choices"]) > 0:
                            delta = chunk_data["choices"][0].get("delta", {})
                            if "content" in delta:
                                chunks.append(delta["content"])
                    except json.JSONDecodeError:
                        pass
            
            if chunks:
                print(f"✅ 流式响应成功")
                print(f"📝 接收到 {len(chunks)} 个数据块")
                print(f"内容预览: {''.join(chunks)[:200]}...")
                return True
            else:
                print("⚠️  未接收到流式数据")
                return False
                
    except Exception as e:
        print(f"❌ 流式响应失败: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="测试 NotebookLM API 服务器")
    parser.add_argument("--host", default="localhost", help="服务器主机 (默认: localhost)")
    parser.add_argument("--port", type=int, default=8000, help="服务器端口 (默认: 8000)")
    parser.add_argument("--api-key", help="API 密钥")
    parser.add_argument("--notebook-id", help="Notebook ID (用于测试)")
    parser.add_argument("--skip-chat", action="store_true", help="跳过聊天测试 (需要认证)")
    
    args = parser.parse_args()
    
    base_url = f"http://{args.host}:{args.port}"
    
    print("=" * 60)
    print(f"NotebookLM API 测试")
    print(f"服务器: {base_url}")
    print("=" * 60)
    
    results = []
    
    # 测试健康检查
    results.append(("健康检查", test_health(base_url)))
    
    # 测试模型列表
    results.append(("模型列表", test_models(base_url, args.api_key)))
    
    # 测试聊天完成 (需要认证)
    if not args.skip_chat:
        if not args.notebook_id:
            print("\n⚠️  警告: 未提供 --notebook-id，聊天测试可能失败")
            print("如果服务器未设置 NOTEBOOKLM_NOTEBOOK_ID 环境变量")
        
        results.append(("聊天完成", test_chat_completion(base_url, args.api_key, args.notebook_id)))
        results.append(("流式响应", test_streaming(base_url, args.api_key, args.notebook_id)))
    else:
        print("\n⏭️  跳过聊天测试")
    
    # 总结
    print("\n" + "=" * 60)
    print("测试总结")
    print("=" * 60)
    
    for name, passed in results:
        status = "✅ 通过" if passed else "❌ 失败"
        print(f"{name:20s} {status}")
    
    total = len(results)
    passed = sum(1 for _, p in results if p)
    
    print(f"\n总计: {passed}/{total} 测试通过")
    
    if passed == total:
        print("\n🎉 所有测试通过！")
        return 0
    else:
        print(f"\n⚠️  {total - passed} 个测试失败")
        return 1


if __name__ == "__main__":
    sys.exit(main())
