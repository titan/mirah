# Copyright (c) 2012 The Mirah project authors. All Rights Reserved.
# All contributing project authors may be found in the NOTICE file.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package org.mirah.jvm.compiler

import java.util.Collections
import java.util.logging.Logger
import javax.tools.DiagnosticListener
import mirah.lang.ast.*
import org.mirah.typer.Typer
import org.mirah.macros.Compiler as MacroCompiler
import org.mirah.util.Context
import org.mirah.util.MirahDiagnostic

import java.util.ArrayList

# Moves class-level field and constant initialization into the constructors/static initializer.
# TODO: generate synthetic/bridge methods.
# TODO: check for errors like undefined abstract methods or duplicate methods
class ClassCleanup < NodeScanner
  def initialize(context:Context, klass:ClassDefinition)
    @context = context
    @typer = context[Typer]
    @parser = context[MacroCompiler]
    @klass = klass
    @static_init_nodes = ArrayList.new
    @init_nodes = ArrayList.new
    @constructors = ArrayList.new
  end
  def clean:void
    scan(@klass.body, nil)
    unless @static_init_nodes.isEmpty
      if @cinit.nil?
        @cinit = @parser.quote { def self.initialize:void; end }
        @typer.infer(@cinit, false)
        @klass.body.add(@cinit)
      end
      nodes = NodeList.new
      @static_init_nodes.each do |n|
        node = Node(n)
        node.parent.removeChild(node)
        nodes.add(node)
      end
      @typer.infer(nodes, false)
      old_body = @cinit.body
      @cinit.body = nodes
      @cinit.body.add(old_body)
    end
    if @constructors.isEmpty 
      add_default_constructor unless @klass.kind_of?(InterfaceDeclaration)
    else
      cleanup = ConstructorCleanup.new(@context)
      init = if @init_nodes.nil?
        nil
      else
        NodeList.new(@init_nodes)
      end
      @constructors.each do |n|
        cleanup.clean(ConstructorDefinition(n), init)
      end
    end
  end
  def add_default_constructor
    constructor = @parser.quote { def initialize; end }
    constructor.body.add(Super.new(constructor.position, Collections.emptyList, nil))
    @klass.body.add(constructor)
    @typer.infer(constructor)
    @constructors.add(constructor)
  end
  def error(message:String, position:Position)
    @context[DiagnosticListener].report(MirahDiagnostic.error(position, message))
  end
  def note(message:String, position:Position)
    @context[DiagnosticListener].report(MirahDiagnostic.note(position, message))
  end
  def enterDefault(node, arg)
    error("Statement not enclosed in a method", node.position)
    false
  end
  def enterMethodDefinition(node, arg)
    false
  end
  def enterStaticMethodDefinition(node, arg)
    if "initialize".equals(node.name.identifier)
      setCinit(node)
    end
    false
  end
  def isStatic(node:Node)
    @typer.scoper.getScope(node).selfType.resolve.isMeta
  end
  def setCinit(node:MethodDefinition):void
    unless @cinit.nil?
      error("Duplicate static initializer", node.position)
      note("Previously declared here", @cinit.position) if @cinit.position
      return
    end
    @cinit = node
  end
  def enterConstructorDefinition(node, arg)
    @constructors.add(node)
    false
  end
  
  def enterClassDefinition(node, arg)
    ClassCleanup.new(@context, node).clean
    false
  end
  def enterInterfaceDeclaration(node, arg)
    enterClassDefinition(node, arg)
    false
  end
  def enterNodeList(node, arg)
    # Scan the children
    true
  end
  def enterClassAppendSelf(node, arg)
    # Scan the children
    true
  end
  def enterConstantAssign(node, arg)
    @static_init_nodes.add(node)
    false
  end
  def enterFieldAssign(node, arg)
    if node.isStatic || isStatic(node)
      @static_init_nodes.add(node)
    else
      @init_nodes.add(node)
    end
  end
end
