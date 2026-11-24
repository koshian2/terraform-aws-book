"""商品相談。履歴を捨てる不具合と、保持する実装を同じ条件で比較する。"""
import os
import threading

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from strands import Agent, tool
from strands.models import BedrockModel

app = BedrockAgentCoreApp()
PRODUCTS = {
    "P001": {"name": "ノート", "unit_price": 300},
    "P002": {"name": "ペン", "unit_price": 150},
}
SYSTEM = """あなたは文具店の商品相談担当です。日本語で簡潔に回答してください。
商品情報と価格は必ずツールで確認し、存在しない商品や価格を創作しないでください。
見積もりはcalculate_quoteで計算してください。商品の内訳・合計・予算内かを示します。
追加依頼ではそれまでの会話の購入品と予算を引き継ぎ、指定された箇所だけ変更します。
会話に情報がなく対象や予算が不明な場合は推測せず確認してください。
購入や予約は行わず、見積もりのみ回答してください。"""


@tool
def lookup_product(product_id: str) -> dict:
    """商品IDで価格を調べる。P001はノート、P002はペン。それ以外は未登録。"""
    product = PRODUCTS.get(product_id)
    return {"product_id": product_id, **product} if product else {"status": "NOT_FOUND", "product_id": product_id}


@tool
def calculate_quote(items: list[dict], budget: int) -> dict:
    """商品の合計と予算内かを計算する。itemsはproduct_idとquantityの配列。budgetは円。"""
    if not items or len(items) > 10 or type(budget) is not int or not 0 <= budget <= 100000:
        return {"error": "invalid_quote"}
    lines = []
    for item in items:
        pid, quantity = item.get("product_id"), item.get("quantity")
        if pid not in PRODUCTS:
            return {"status": "NOT_FOUND", "product_id": pid}
        if type(quantity) is not int or not 1 <= quantity <= 100:
            return {"error": "invalid_quantity"}
        product = PRODUCTS[pid]
        lines.append({"product_id": pid, **product, "quantity": quantity,
                      "subtotal": product["unit_price"] * quantity})
    total = sum(line["subtotal"] for line in lines)
    return {"items": lines, "total": total, "budget": budget,
            "within_budget": total <= budget, "currency": "JPY"}


# Runtimeセッションの存続中のみ保持する。永続化や長期記憶の例ではない。
agents = {}
lock = threading.Lock()


@app.entrypoint
def invoke(payload, context):
    prompt = payload.get("prompt", "")
    variant = payload.get("variant", "fixed")
    if variant not in ("forgetful", "fixed") or not isinstance(prompt, str) or not 1 <= len(prompt) <= 2000:
        raise ValueError("variant must be forgetful/fixed; prompt must be 1..2000 characters")
    sid = context.session_id
    with lock:
        agent = agents.get(sid)
        if agent is None or variant == "forgetful":
            # 不具合の再現: 同じセッションでもAgentを作り直すと会話履歴を失う。
            agent = Agent(name="StationeryAssistant", system_prompt=SYSTEM,
                          model=BedrockModel(model_id=os.environ["MODEL_ID"], max_tokens=2048),
                          tools=[lookup_product, calculate_quote], callback_handler=None,
                          trace_attributes={"session.id": sid, "demo.variant": variant})
            agents[sid] = agent
        result = agent(prompt)
        return {"session_id": sid, "variant": variant, "answer": str(result)}


def main():
    app.run()


if __name__ == "__main__":
    main()
