// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:wasmjsgen/src/code_generator.dart';

import 'binding.dart';
import 'binding_string.dart';
import 'type.dart';
import 'utils.dart';
import 'writer.dart';

// NOTE: at this point wasmjsgen only supports opaque structs
const FORCE_OPAQUE = true;

enum CompoundType { struct, union }

/// A binding for Compound type - Struct/Union.
abstract class Compound extends NoLookUpBinding {
  /// Marker for if a struct definition is complete.
  ///
  /// A function can be safely pass this struct by value if it's complete.
  bool isInComplete;

  List<Member> members;

  bool get isOpaque => members.isEmpty;

  /// Value for `@Packed(X)` annotation. Can be null(no packing), 1, 2, 4, 8, 16.
  ///
  /// Only supported for [CompoundType.struct].
  int? pack;

  /// Marker for checking if the dependencies are parsed.
  bool parsedDependencies = false;

  CompoundType compoundType;
  bool get isStruct => compoundType == CompoundType.struct;
  bool get isUnion => compoundType == CompoundType.union;

  Compound({
    String? usr,
    String? originalName,
    required String name,
    required this.compoundType,
    this.isInComplete = false,
    this.pack,
    String? dartDoc,
    List<Member>? members,
  })  : members = members ?? [],
        super(
          usr: usr,
          originalName: originalName,
          name: name,
          dartDoc: dartDoc,
        );

  factory Compound.fromType({
    required CompoundType type,
    String? usr,
    String? originalName,
    required String name,
    bool isInComplete = false,
    int? pack,
    String? dartDoc,
    List<Member>? members,
  }) {
    switch (type) {
      case CompoundType.struct:
        return Struc(
          usr: usr,
          originalName: originalName,
          name: name,
          isInComplete: isInComplete,
          pack: pack,
          dartDoc: dartDoc,
          members: members,
        );
      case CompoundType.union:
        return Union(
          usr: usr,
          originalName: originalName,
          name: name,
          isInComplete: isInComplete,
          pack: pack,
          dartDoc: dartDoc,
          members: members,
        );
    }
  }

  @override
  BindingString toBindingString(Writer w) {
    final s = StringBuffer();
    final enclosingClassName = name;
    if (dartDoc != null) {
      s.write(makeDartDoc(dartDoc!));
    }

    /// Adding [enclosingClassName] because dart doesn't allow class member
    /// to have the same name as the class.
    final localUniqueNamer = UniqueNamer({enclosingClassName});

    /// Write @Packed(X) annotation if struct is packed.
    if (isStruct && pack != null) {
      s.write('// @Packed($pack)\n');
    }
    final dartClassName = isStruct ? 'Struct' : 'Union';
    // Write class declaration.
    if (FORCE_OPAQUE || isOpaque) {
      s.writeln('class $enclosingClassName extends Opaque {');
      s.writeln('  $enclosingClassName(int address) : super(address);');
    } else {
      s.write('class $enclosingClassName extends $dartClassName {\n');
    }
    const depth = '  ';
    if (!FORCE_OPAQUE) {
      for (final m in members) {
        final memberName = localUniqueNamer.makeUnique(m.name);
        if (m.type.broadType == BroadType.ConstantArray) {
          assert(false,
              'wasmjs does not handle ConstantArray yet like ffigen does');
        } else {
          if (m.dartDoc != null) {
            s.write(depth + '/// ');
            s.writeAll(m.dartDoc!.split('\n'), '\n' + depth + '/// ');
            s.write('\n');
          }
          if (!m.type.sameDartAndCType(w)) {
            s.write('$depth@${m.type.getCType(w)}()\n');
          }
          s.write('${depth}external ${m.type.getDartType(w)} $memberName;\n\n');
        }
      }
    }
    s.write('}\n\n');

    return BindingString(
        type: isStruct ? BindingStringType.struc : BindingStringType.union,
        string: s.toString());
  }

  @override
  void addDependencies(Set<Binding> dependencies) {
    if (dependencies.contains(this)) return;

    dependencies.add(this);
    for (final m in members) {
      m.type.addDependencies(dependencies);
    }
  }
}

class Member {
  final String? dartDoc;
  final String originalName;
  final String name;
  final Type type;

  const Member({
    String? originalName,
    required this.name,
    required this.type,
    this.dartDoc,
  }) : originalName = originalName ?? name;
}
