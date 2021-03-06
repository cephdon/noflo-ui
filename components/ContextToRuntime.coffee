noflo = require 'noflo'
_ = require 'underscore'

sendContext = (context, out) ->
  if context.project
    sendProject context.project, context.runtime
    out.send context
    out.disconnect()
    return

  if context.graphs?.length
    sendGraph null, graph, context.runtime for graph in context.graphs
    out.send context
    out.disconnect()
    return

  out.send context
  out.disconnect()

sendProject = (project, runtime) ->
  namespace = project.namespace or project.id
  if project.components
    sendComponent namespace, component, runtime for component in project.components
  if project.graphs
    sendGraph namespace, graph, runtime, project for graph in project.graphs

sendComponent = (namespace, component, runtime) ->
  return unless component.code

  # Check for platform-specific components
  runtimeType = component.code.match /@runtime ([a-z\-]+)/
  if runtimeType
    return unless runtimeType[1] in ['all', runtime.definition.type]

  return unless runtime.canDo 'component:setsource'

  runtime.sendComponent 'source',
    name: component.name
    language: component.language
    library: namespace
    code: component.code
    tests: component.tests

sendGraph = (namespace, graph, runtime, project) ->
  if graph.properties.environment?.type
    return unless graph.properties.environment.type in ['all', runtime.definition.type]

  return unless runtime.canDo 'protocol:graph'

  graphId = graph.name or graph.properties.id
  runtime.sendGraph 'clear',
    id: graphId
    name: graph.name
    library: namespace
    main: (not project or graph.properties.id is project.main)
    icon: graph.properties.icon or ''
    description: graph.properties.description or ''
  for node in graph.nodes
    runtime.sendGraph 'addnode',
      id: node.id
      component: node.component
      metadata: node.metadata
      graph: graphId
  for edge in graph.edges
    runtime.sendGraph 'addedge',
      src:
        node: edge.from.node
        port: edge.from.port
      tgt:
        node: edge.to.node
        port: edge.to.port
      metadata: edge.metadata
      graph: graphId
  for iip in graph.initializers
    runtime.sendGraph 'addinitial',
      src:
        data: iip.from.data
      tgt:
        node: iip.to.node
        port: iip.to.port
      metadata: iip.metadata
      graph: graphId
  if graph.inports
    for pub, priv of graph.inports
      runtime.sendGraph 'addinport',
        public: pub
        node: priv.process
        port: priv.port
        graph: graphId
  if graph.outports
    for pub, priv of graph.outports
      runtime.sendGraph 'addoutport',
        public: pub
        node: priv.process
        port: priv.port
        graph: graphId

currentContext = null

exports.getComponent = ->
  c = new noflo.Component
  c.inPorts.add 'context',
    datatype: 'object'
    process: (event, payload) ->
      return unless event is 'data'
      return unless payload.runtime
      if currentContext?.runtime and currentContext.graphs[0] isnt payload.graphs[0] and sender
        currentContext.runtime.removeListener 'capabilities', sender
        if currentContext.runtime is payload.runtime
          # Same runtime, different graph. Reconnect to clear caches
          currentContext.runtime.reconnect()
        else
          # Different runtime, different graph. Disconnect old runtime connection
          currentContext.runtime.disconnect()

      send = _.debounce sendContext, 300, true

      # Prepare to send data
      currentContext = payload
      send payload, c.outPorts.context if payload.runtime.isConnected()
      sender = ->
        return unless currentContext is payload
        send payload, c.outPorts.context

      payload.runtime.on 'capabilities', sender

  c.outPorts.add 'context',
    datatype: 'object'

  c
