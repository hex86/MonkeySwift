//===-- Evaluator ---------------------------------------------*- Swift -*-===//
//
// This file implements the monkey evaluator, a function that will take an
// AST Node and return an Object.
//
//===----------------------------------------------------------------------===//

public func eval(_ node: Node, _ env: inout Enviroment) -> Object {
  //===-*- Statements -*--===//
  if let n = node as? Program {
    return evalProgram(n, &env)
  }
  if let n = node as? BlockStatement {
    return evalBlockStatement(n, &env)
  }
  if let n = node as? ExpressionStatement {
    return eval(n.expression, &env)
  }
  if let n = node as? ReturnStatement {
    let val = eval(n.returnValue, &env)
    return isError(val) ? val : ReturnValue(value: val)
  }
  if let n = node as? LetStatement {
    let val = eval(n.value, &env)
    if isError(val) {
      return val
    }
    env[n.name.value] = val
    return val
  }

  //===-*- Expressions -*-===//
  if let n = node as? IntegerLiteral {
    return Integer(value: n.value)
  }
  if let n = node as? BooleanExpression {
    return Boolean(value: n.value)
  }
  if let n = node as? PrefixExpression {
    let right = eval(n.right, &env)
    return isError(right) ? right : evalPrefixExpression(n.operator, right)
  }
  if let n = node as? InfixExpression {
    let left = eval(n.left, &env)
    if isError(left) {
      return left
    }
    let right = eval(n.right, &env)
    return isError(right) ? right : evalInfixExpression(n.operator, left, right)
  }
  if let n = node as? IfExpression {
    return evalIfExpression(n, &env)
  }
  if let n = node as? Identifier {
    return evalIdentifier(n, &env)
  }
  if let n = node as? FunctionLiteral {
    let params = n.parameters
    let body = n.body
    return Function(parameters: params, body: body, env: env)
  }
  if let n = node as? CallExpression {
    let function = eval(n.function, &env)
    if isError(function) {
      return function
    }
    let args = evalExpressions(n.arguments, &env)
    if args.count == 1 && isError(args[0]) {
      return args[0]
    }
    return applyFunction(function, args)
  }
  if let n = node as? StringLiteral {
    return StringObj(value: n.value)
  }
  if let n = node as? ArrayLiteral {
    let elements = evalExpressions(n.elements, &env)
    if elements.count == 1 && isError(elements[0]) {
      return elements[0]
    }
    return ArrayObj(elements: elements)
  }
  if let n = node as? IndexExpression {
    let left = eval(n.left, &env)
    if isError(left) {
      return left
    }
    let index = eval(n.index, &env)
    if isError(index) {
      return index
    }
    return evalIndexExpression(left, index)
  }
  if let n = node as? HashLiteral {
    return evalHashLiteral(n, &env)
  }
  return ErrorObj(message: "evaluation of \(type(of: node)) not implemented")
}

func evalProgram(_ program: Program, _ env: inout Enviroment) -> Object {
  var result: Object!
  for stmt in program.statements {
    result = eval(stmt, &env)
    if let returnValue = result as? ReturnValue {
      return returnValue.value
    }
    if result is ErrorObj {
      return result
    }
  }
  return result
}

func evalPrefixExpression(_ op: String, _ right: Object) -> Object {
  switch op {
  case "!": return evalBangOperatorExpression(right)
  case "-": return evalMinusPrefixOperatorExpression(right)
  default:
    return ErrorObj(message: "unknown operator: \(op)\(right.type)")
  }
}

func evalBangOperatorExpression(_ right: Object) -> Object {
  let TRUE  = Boolean(value:  true)
  let FALSE = Boolean(value: false)
  if let r = right as? Boolean {
    return r == TRUE ? FALSE : TRUE
  }
  if right is Null {
    return TRUE
  }
  return FALSE
}

func evalMinusPrefixOperatorExpression(_ right: Object) -> Object {
  if right.type != .integer {
    return ErrorObj(message: "unknown operator: -\(right.type)")
  }
  return Integer(value: -(right as! Integer).value)
}

func evalInfixExpression(_ op: String, _ left: Object, _ right: Object) -> Object {
  if left.type == .integer && right.type == .integer {
    return evalIntegerInfixExpression(op, left, right)
  }
  if left.type == .string && right.type == .string {
    return evalStringInfixExpression(op, left, right)
  }
  if op == "==" {
    let leftVal  =  left as! Boolean
    let rightVal = right as! Boolean
    return Boolean(value: leftVal == rightVal)
  }
  if op == "!=" {
    let leftVal  =  left as! Boolean
    let rightVal = right as! Boolean
    return Boolean(value: leftVal != rightVal)
  }
  if left.type != right.type {
    return ErrorObj(message: "type mismatch: \(left.type) \(op) \(right.type)")
  }
  return ErrorObj(message: "unknown operator: \(left.type) \(op) \(right.type)")
}

func evalIntegerInfixExpression(_ op: String, _ left: Object, _ right: Object) -> Object {
  let leftVal  = ( left as! Integer).value
  let rightVal = (right as! Integer).value
  switch op {
    case "+" : return Integer(value: leftVal +  rightVal)
    case "-" : return Integer(value: leftVal -  rightVal)
    case "*" : return Integer(value: leftVal *  rightVal)
    case "/" : return Integer(value: leftVal /  rightVal)
    case ">" : return Boolean(value: leftVal >  rightVal)
    case "<" : return Boolean(value: leftVal <  rightVal)
    case "==": return Boolean(value: leftVal == rightVal)
    case "!=": return Boolean(value: leftVal != rightVal)
    default:
      return ErrorObj(message: "unknown operator: \(left.type) \(op) \(right.type)")
  }
}

func evalStringInfixExpression(_ op: String, _ left: Object, _ right: Object) -> Object {
  if op != "+" {
    return ErrorObj(message: "unknown operator: \(left.type) \(op) \(right.type)")
  }
  let leftVal  = ( left as! StringObj).value
  let rightVal = (right as! StringObj).value
  return StringObj(value: leftVal + rightVal)
}

func evalIfExpression(_ e: IfExpression, _ env: inout Enviroment) -> Object {
  let condition = eval(e.condition, &env)
  if isError(condition) {
    return condition
  }
  if isTruthy(condition) {
    return eval(e.consequence, &env)
  } else if let alt = e.alternative {
    return eval(alt, &env)
  } else {
    return Null()
  }
}

func evalBlockStatement(_ block: BlockStatement, _ env: inout Enviroment) -> Object {
  var result: Object!
  for stmt in block.statements {
    result = eval(stmt, &env)
    if result.type == .returnValue || result.type == .error {
      return result
    }
  }
  return result
}

func evalIdentifier(_ node: Identifier, _ env: inout Enviroment) -> Object {
  if let val = env[node.value] {
    return val
  }
  if let builtin = builtins[node.value] {
    return builtin
  }
  return ErrorObj(message: "identifier \(node.value) not found!")
}

func evalExpressions(_ exps: [Expression], _ env: inout Enviroment) -> [Object] {
  var result: [Object] = []
  for exp in exps {
    let evaluated = eval(exp, &env)
    if isError(evaluated) {
      return [evaluated]
    }
    result.append(evaluated)
  }
  return result
}

func evalIndexExpression(_ left: Object, _ index: Object) -> Object {
  if let l = left as? ArrayObj {
    return evalArrayIndexExpression(l, index)
  } else if let l = left as? Hash {
    return evalHashIndexExpression(l, index)
  }
  return ErrorObj(message: "index operator not supported: \(type(of: left))")
}

func evalArrayIndexExpression(_ array: Object, _ index: Object) -> Object {
  let arrayObject = array as! ArrayObj
  let idx         = (index as! Integer).value
  let max         = Int64(arrayObject.elements.count) - 1
  if idx < 0 || idx > max {
    return Null()
  }
  return arrayObject.elements[Int(idx)]
}

func evalHashLiteral(_ node: HashLiteral, _ env: inout Enviroment) -> Object {
  var store: [AnyHashable: Object] = [:]
  for (keyNode, valueNode) in node.store {
    let key = eval(keyNode as! Expression, &env)
    if isError(key) {
      return key
    }
    let value = eval(valueNode, &env)
    if isError(key) {
      return key
    }
    guard let rKey = key as? AnyHashable else {
      return ErrorObj(message: "unusable as hash key: \(type(of: key))")
    }
    store[rKey] = value
  }
  return Hash(store: store)
}

func evalHashIndexExpression(_ hash: Object, _ index: Object) -> Object {
  let hashObj = hash as! Hash
  guard let key = index as? AnyHashable else {
    return ErrorObj(message: "unusable as hash key: \(type(of: index))")
  }
  guard let value = hashObj.store[key] else {
    return Null()
  }
  return value
}

func applyFunction(_ fn: Object, _ args: [Object]) -> Object {
  if let function = fn as? Function {
    var extendedEnv = extendFunctionEnv(function, args)
    let evaluated   = eval(function.body, &extendedEnv)
    return unwrapReturnValue(evaluated)
  }
  if let function = fn as? Builtin {
    let fn = unsafeBitCast(function.fn, to: (([Object]) -> Object).self)
    return fn(args)
  }
  return ErrorObj(message: "not a function: \(fn.type)")
}

func extendFunctionEnv(_ fn: Function, _ args: [Object]) -> Enviroment {
  let env = Enviroment(outer: fn.env)
  for (i, param) in fn.parameters.enumerated() {
    env[param.value] = args[i]
  }
  return env
}

func unwrapReturnValue(_ obj: Object) -> Object {
  if let returnValue = obj as? ReturnValue {
    return returnValue.value
  }
  return obj
}

func isTruthy(_ obj: Object) -> Bool {
  obj is Boolean ? (obj as! Boolean).value : !(obj is Null)
}

func isError(_ obj: Object) -> Bool { obj.type == .error }
