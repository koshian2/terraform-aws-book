"""Bounded arithmetic only: no eval, names, calls or external access."""
import ast
from decimal import Decimal, localcontext
from strands import tool


def arithmetic(expression):
    if len(expression) > 200:
        raise ValueError("Expression too long")
    tree = ast.parse(expression, mode="eval")
    if len(list(ast.walk(tree))) > 80:
        raise ValueError("Expression too complex")

    def visit(node):
        if isinstance(node, ast.Constant) and type(node.value) is int and abs(node.value) <= 10**12:
            return Decimal(node.value)
        if isinstance(node, ast.BinOp):
            left, right = visit(node.left), visit(node.right)
            if isinstance(node.op, ast.Add): return left + right
            if isinstance(node.op, ast.Sub): return left - right
            if isinstance(node.op, ast.Mult): return left * right
            if isinstance(node.op, ast.Div): return left / right
        raise ValueError("Use integer operands, + - * / and parentheses only")

    with localcontext() as ctx:
        ctx.prec = 28
        result = visit(tree.body)
    if not result.is_finite() or abs(result) > 10**15:
        raise ValueError("Result out of range")
    return format(result, "f")


def calculation_tool(records):
    @tool
    def calculate(expression: str, purpose: str) -> str:
        """Calculate using integer operands from the supplied meeting documents.

        Args:
            expression: Arithmetic expression with + - * / and parentheses; no code or names.
            purpose: Ingredient and calculation purpose, including units.
        """
        if len(records) >= 24 or len(purpose) > 200:
            raise ValueError("Calculation budget exceeded")
        result = arithmetic(expression)
        records.append({"purpose": purpose, "expression": expression, "result": result})
        return result
    return calculate
