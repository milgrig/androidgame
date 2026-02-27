"""
Unit tests for subgroup engine: Permutation extensions, KeyRing subgroup checks,
and SubgroupChecker (normality, cosets, lattice).
Python mirrors of GDScript logic for executable verification.
Tests validate the mathematical correctness for Act 2 subgroup mechanics.
"""
import itertools
import unittest


# === Python mirrors of GDScript classes ===

class Permutation:
    def __init__(self, mapping: list[int]):
        self.mapping = list(mapping)

    def size(self) -> int:
        return len(self.mapping)

    def apply(self, i: int) -> int:
        return self.mapping[i]

    def is_valid(self) -> bool:
        n = self.size()
        return n > 0 and sorted(self.mapping) == list(range(n))

    def is_identity(self) -> bool:
        return all(self.mapping[i] == i for i in range(self.size()))

    def compose(self, other: "Permutation") -> "Permutation":
        assert self.size() == other.size()
        return Permutation([other.apply(self.apply(i)) for i in range(self.size())])

    def inverse(self) -> "Permutation":
        inv = [0] * self.size()
        for i, v in enumerate(self.mapping):
            inv[v] = i
        return Permutation(inv)

    def order(self) -> int:
        current = self
        identity = Permutation.create_identity(self.size())
        for k in range(1, 1000):
            if current.equals(identity):
                return k
            current = current.compose(self)
        return -1

    def equals(self, other: "Permutation") -> bool:
        return self.mapping == other.mapping

    def to_cycle_notation(self) -> str:
        visited = set()
        cycles = []
        for i in range(self.size()):
            if i in visited:
                continue
            cycle = []
            j = i
            while j not in visited:
                visited.add(j)
                cycle.append(j)
                j = self.mapping[j]
            if len(cycle) > 1:
                cycles.append("(" + " ".join(str(c) for c in cycle) + ")")
        return "".join(cycles) if cycles else "()"

    def is_in_group(self, group: list["Permutation"]) -> bool:
        """Check if this permutation belongs to the given group."""
        return any(self.equals(g) for g in group)

    @staticmethod
    def create_identity(n: int) -> "Permutation":
        return Permutation(list(range(n)))

    @staticmethod
    def compose_list(perms: list["Permutation"], n: int = 0) -> "Permutation":
        """Compose a list of permutations left-to-right."""
        if not perms:
            return Permutation.create_identity(n if n > 0 else 1)
        result = perms[0]
        for p in perms[1:]:
            result = result.compose(p)
        return result

    @staticmethod
    def generate_subgroup_from(generators: list["Permutation"], n: int) -> list["Permutation"]:
        """Generate the subgroup from given generators via iterative closure."""
        subgroup = [Permutation.create_identity(n)]

        for gen in generators:
            if not any(s.equals(gen) for s in subgroup):
                subgroup.append(gen)

        changed = True
        while changed:
            changed = False
            to_add = []
            # Close under composition
            for a in subgroup:
                for b in subgroup:
                    product = a.compose(b)
                    if not any(s.equals(product) for s in subgroup) and \
                       not any(t.equals(product) for t in to_add):
                        to_add.append(product)
            # Close under inverse
            for a in subgroup:
                inv = a.inverse()
                if not any(s.equals(inv) for s in subgroup) and \
                   not any(t.equals(inv) for t in to_add):
                    to_add.append(inv)
            if to_add:
                subgroup.extend(to_add)
                changed = True

        return subgroup


class KeyRing:
    def __init__(self, target_count: int = 0):
        self.found: list[Permutation] = []
        self.target_count = target_count

    def add_key(self, p: Permutation) -> bool:
        if self.contains(p):
            return False
        self.found.append(p)
        return True

    def contains(self, p: Permutation) -> bool:
        return any(k.equals(p) for k in self.found)

    def count(self) -> int:
        return len(self.found)

    def _index_of(self, p: Permutation) -> int:
        for i, f in enumerate(self.found):
            if f.equals(p):
                return i
        return -1

    def check_subgroup(self, key_indices: list[int]) -> dict:
        """Check whether subset of keys forms a subgroup."""
        subset = [self.found[i] for i in key_indices if 0 <= i < len(self.found)]
        result = {"is_subgroup": True, "missing_elements": [], "reasons": []}

        # Identity check
        if not any(p.is_identity() for p in subset):
            result["is_subgroup"] = False
            result["reasons"].append("missing_identity")

        # Composition closure check
        for a in subset:
            for b in subset:
                product = a.compose(b)
                if not any(s.equals(product) for s in subset):
                    result["is_subgroup"] = False
                    if not any(m.equals(product) for m in result["missing_elements"]):
                        result["missing_elements"].append(product)
                    if "not_closed_composition" not in result["reasons"]:
                        result["reasons"].append("not_closed_composition")

        # Inverse closure check
        for a in subset:
            inv = a.inverse()
            if not any(s.equals(inv) for s in subset):
                result["is_subgroup"] = False
                if not any(m.equals(inv) for m in result["missing_elements"]):
                    result["missing_elements"].append(inv)
                if "missing_inverse" not in result["reasons"]:
                    result["reasons"].append("missing_inverse")

        return result

    def get_subgroup_closure(self, key_indices: list[int]) -> list[int]:
        """Generate the closure of the subset and return indices into found[]."""
        generators = [self.found[i] for i in key_indices if 0 <= i < len(self.found)]
        if not generators:
            return []
        n = generators[0].size()
        closed = Permutation.generate_subgroup_from(generators, n)
        result_indices = []
        for c in closed:
            idx = self._index_of(c)
            if idx != -1 and idx not in result_indices:
                result_indices.append(idx)
        result_indices.sort()
        return result_indices

    def find_all_subgroups(self) -> list[dict]:
        """Find all subgroups among the found keys by full subset enumeration."""
        n = len(self.found)
        if n == 0:
            return []
        subgroups = []
        for mask in range(1, 1 << n):
            subset = []
            indices = []
            for bit in range(n):
                if mask & (1 << bit):
                    subset.append(self.found[bit])
                    indices.append(bit)
            if self._is_subset_subgroup(subset):
                subgroups.append({
                    "indices": indices,
                    "order": len(subset),
                    "elements": subset
                })
        return subgroups

    @staticmethod
    def _is_subset_subgroup(subset: list[Permutation]) -> bool:
        if not any(p.is_identity() for p in subset):
            return False
        for a in subset:
            for b in subset:
                product = a.compose(b)
                if not any(s.equals(product) for s in subset):
                    return False
        for a in subset:
            inv = a.inverse()
            if not any(s.equals(inv) for s in subset):
                return False
        return True


class SubgroupChecker:
    @staticmethod
    def is_normal(subgroup: list[Permutation], group: list[Permutation]) -> bool:
        """Check if subgroup H is normal in group G: ∀g∈G, ∀h∈H: g·h·g⁻¹ ∈ H"""
        for g in group:
            g_inv = g.inverse()
            for h in subgroup:
                conjugate = g.compose(h).compose(g_inv)
                if not any(s.equals(conjugate) for s in subgroup):
                    return False
        return True

    @staticmethod
    def coset_decomposition(subgroup: list[Permutation],
                            group: list[Permutation]) -> list[list[Permutation]]:
        """Compute left coset decomposition of G by H."""
        cosets = []
        assigned = []
        for g in group:
            if any(a.equals(g) for a in assigned):
                continue
            coset = []
            for h in subgroup:
                element = g.compose(h)
                coset.append(element)
                assigned.append(element)
            cosets.append(coset)
        return cosets

    @staticmethod
    def lattice(group: list[Permutation]) -> dict:
        """Build the subgroup lattice of the given group."""
        if not group:
            return {"subgroups": [], "inclusions": []}
        n = group[0].size()
        all_subgroups = []
        seen_signatures = set()

        candidate_gen_sets = []
        # Single generators
        for g in group:
            candidate_gen_sets.append([g])
        # Pairs
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                candidate_gen_sets.append([group[i], group[j]])

        for gens in candidate_gen_sets:
            sub = Permutation.generate_subgroup_from(gens, n)
            sig = _subgroup_signature(sub)
            if sig not in seen_signatures:
                seen_signatures.add(sig)
                all_subgroups.append(sub)

        subgroup_info = [{"elements": sub, "order": len(sub)} for sub in all_subgroups]

        # Build inclusion edges (direct inclusions only)
        inclusions = []
        for i in range(len(all_subgroups)):
            for j in range(len(all_subgroups)):
                if i == j:
                    continue
                if len(all_subgroups[i]) >= len(all_subgroups[j]):
                    continue
                if _is_subset_of(all_subgroups[i], all_subgroups[j]):
                    # Check directness
                    is_direct = True
                    for k in range(len(all_subgroups)):
                        if k == i or k == j:
                            continue
                        if (len(all_subgroups[k]) > len(all_subgroups[i]) and
                                len(all_subgroups[k]) < len(all_subgroups[j]) and
                                _is_subset_of(all_subgroups[i], all_subgroups[k]) and
                                _is_subset_of(all_subgroups[k], all_subgroups[j])):
                            is_direct = False
                            break
                    if is_direct:
                        inclusions.append([i, j])

        return {"subgroups": subgroup_info, "inclusions": inclusions}


def _subgroup_signature(sub: list[Permutation]) -> str:
    mappings = sorted(",".join(str(v) for v in p.mapping) for p in sub)
    return "|".join(mappings)


def _is_subset_of(sub_a: list[Permutation], sub_b: list[Permutation]) -> bool:
    for a in sub_a:
        if not any(b.equals(a) for b in sub_b):
            return False
    return True


# === Helper: build S3 group ===

def build_s3() -> list[Permutation]:
    """All 6 permutations of S3."""
    return [Permutation(list(p)) for p in itertools.permutations(range(3))]


def build_z3() -> list[Permutation]:
    """Z3 = {e, (0 1 2), (0 2 1)} as rotations."""
    return [
        Permutation([0, 1, 2]),  # e
        Permutation([1, 2, 0]),  # r
        Permutation([2, 0, 1]),  # r^2
    ]


def build_z2_swap01() -> list[Permutation]:
    """Z2 generated by swap(0,1) in S3."""
    return [
        Permutation([0, 1, 2]),  # e
        Permutation([1, 0, 2]),  # (0 1)
    ]


def build_z2_swap02() -> list[Permutation]:
    """Z2 generated by swap(0,2) in S3."""
    return [
        Permutation([0, 1, 2]),  # e
        Permutation([2, 1, 0]),  # (0 2)
    ]


def build_z2_swap12() -> list[Permutation]:
    """Z2 generated by swap(1,2) in S3."""
    return [
        Permutation([0, 1, 2]),  # e
        Permutation([0, 2, 1]),  # (1 2)
    ]


# === Test Cases ===

class TestPermutationExtensions(unittest.TestCase):
    """Tests for new Permutation methods: compose_list, is_in_group, generate_subgroup_from"""

    def test_compose_list_empty(self):
        result = Permutation.compose_list([], n=3)
        self.assertTrue(result.is_identity())
        self.assertEqual(result.size(), 3)

    def test_compose_list_single(self):
        r = Permutation([1, 2, 0])
        result = Permutation.compose_list([r])
        self.assertTrue(result.equals(r))

    def test_compose_list_two(self):
        r = Permutation([1, 2, 0])
        r2 = r.compose(r)
        result = Permutation.compose_list([r, r])
        self.assertTrue(result.equals(r2))

    def test_compose_list_three_gives_identity(self):
        r = Permutation([1, 2, 0])
        result = Permutation.compose_list([r, r, r])
        self.assertTrue(result.is_identity())

    def test_is_in_group_true(self):
        z3 = build_z3()
        r = Permutation([1, 2, 0])
        self.assertTrue(r.is_in_group(z3))

    def test_is_in_group_false(self):
        z3 = build_z3()
        s = Permutation([0, 2, 1])  # Not in Z3
        self.assertFalse(s.is_in_group(z3))

    def test_generate_subgroup_from_single_rotation(self):
        """Generating from r=[1,2,0] should give Z3 = {e, r, r^2}"""
        r = Permutation([1, 2, 0])
        sub = Permutation.generate_subgroup_from([r], 3)
        self.assertEqual(len(sub), 3)
        # Should contain identity, r, r^2
        mappings = sorted([tuple(p.mapping) for p in sub])
        self.assertEqual(mappings, [(0, 1, 2), (1, 2, 0), (2, 0, 1)])

    def test_generate_subgroup_from_identity(self):
        """Generating from identity should give {e}"""
        e = Permutation.create_identity(3)
        sub = Permutation.generate_subgroup_from([e], 3)
        self.assertEqual(len(sub), 1)
        self.assertTrue(sub[0].is_identity())

    def test_generate_subgroup_from_swap(self):
        """Generating from swap(1,2) should give Z2 = {e, (1 2)}"""
        s = Permutation([0, 2, 1])
        sub = Permutation.generate_subgroup_from([s], 3)
        self.assertEqual(len(sub), 2)

    def test_generate_subgroup_from_two_generators_gives_s3(self):
        """Generating from r and s should give full S3"""
        r = Permutation([1, 2, 0])
        s = Permutation([0, 2, 1])
        sub = Permutation.generate_subgroup_from([r, s], 3)
        self.assertEqual(len(sub), 6)

    def test_generate_subgroup_empty_generators(self):
        """Empty generators should give just {e}"""
        sub = Permutation.generate_subgroup_from([], 3)
        self.assertEqual(len(sub), 1)
        self.assertTrue(sub[0].is_identity())


class TestKeyRingSubgroups(unittest.TestCase):
    """Tests for KeyRing subgroup methods: check_subgroup, get_subgroup_closure, find_all_subgroups"""

    def _build_s3_keyring(self) -> KeyRing:
        """Build a KeyRing containing all S3 elements."""
        kr = KeyRing(6)
        for p in build_s3():
            kr.add_key(p)
        return kr

    def test_check_subgroup_z3_in_s3(self):
        """Z3 = {e, r, r^2} is a subgroup of S3"""
        kr = self._build_s3_keyring()
        # Find indices of Z3 elements
        z3_elements = build_z3()
        indices = []
        for z in z3_elements:
            for i, f in enumerate(kr.found):
                if f.equals(z):
                    indices.append(i)
                    break
        result = kr.check_subgroup(indices)
        self.assertTrue(result["is_subgroup"])
        self.assertEqual(len(result["missing_elements"]), 0)
        self.assertEqual(len(result["reasons"]), 0)

    def test_check_subgroup_z2_in_s3(self):
        """Z2 = {e, (1 2)} is a subgroup of S3"""
        kr = self._build_s3_keyring()
        z2_elements = build_z2_swap12()
        indices = []
        for z in z2_elements:
            for i, f in enumerate(kr.found):
                if f.equals(z):
                    indices.append(i)
                    break
        result = kr.check_subgroup(indices)
        self.assertTrue(result["is_subgroup"])

    def test_not_subgroup(self):
        """Arbitrary subset {r, (1 2)} without identity is NOT a subgroup"""
        kr = self._build_s3_keyring()
        r = Permutation([1, 2, 0])
        s = Permutation([0, 2, 1])
        indices = []
        for target in [r, s]:
            for i, f in enumerate(kr.found):
                if f.equals(target):
                    indices.append(i)
                    break
        result = kr.check_subgroup(indices)
        self.assertFalse(result["is_subgroup"])
        self.assertIn("missing_identity", result["reasons"])

    def test_not_subgroup_no_closure(self):
        """Subset {e, r} is not closed under composition (r*r = r^2 missing)"""
        kr = self._build_s3_keyring()
        e = Permutation([0, 1, 2])
        r = Permutation([1, 2, 0])
        indices = []
        for target in [e, r]:
            for i, f in enumerate(kr.found):
                if f.equals(target):
                    indices.append(i)
                    break
        result = kr.check_subgroup(indices)
        self.assertFalse(result["is_subgroup"])
        self.assertIn("not_closed_composition", result["reasons"])
        # r^2 should be in missing elements
        r2 = Permutation([2, 0, 1])
        self.assertTrue(any(m.equals(r2) for m in result["missing_elements"]))

    def test_closure_z3(self):
        """Closure of {r} in S3 should give indices for {e, r, r^2}"""
        kr = self._build_s3_keyring()
        r = Permutation([1, 2, 0])
        r_idx = -1
        for i, f in enumerate(kr.found):
            if f.equals(r):
                r_idx = i
                break
        closure_indices = kr.get_subgroup_closure([r_idx])
        # Should contain 3 indices (e, r, r^2)
        self.assertEqual(len(closure_indices), 3)
        # Verify the elements at those indices form Z3
        closure_elements = [kr.found[i] for i in closure_indices]
        self.assertTrue(any(p.is_identity() for p in closure_elements))
        self.assertTrue(any(p.equals(r) for p in closure_elements))
        r2 = Permutation([2, 0, 1])
        self.assertTrue(any(p.equals(r2) for p in closure_elements))

    def test_closure_swap_gives_z2(self):
        """Closure of {(1 2)} should give {e, (1 2)}"""
        kr = self._build_s3_keyring()
        s = Permutation([0, 2, 1])
        s_idx = -1
        for i, f in enumerate(kr.found):
            if f.equals(s):
                s_idx = i
                break
        closure_indices = kr.get_subgroup_closure([s_idx])
        self.assertEqual(len(closure_indices), 2)

    def test_find_all_subgroups_s3(self):
        """S3 has exactly 6 subgroups: {e}, 3×Z2, Z3, S3"""
        kr = self._build_s3_keyring()
        subgroups = kr.find_all_subgroups()
        orders = sorted([s["order"] for s in subgroups])
        # {e}(1), Z2(2)×3, Z3(3), S3(6) = [1, 2, 2, 2, 3, 6]
        self.assertEqual(orders, [1, 2, 2, 2, 3, 6])

    def test_find_all_subgroups_z3(self):
        """Z3 has exactly 2 subgroups: {e} and Z3 itself"""
        kr = KeyRing(3)
        for p in build_z3():
            kr.add_key(p)
        subgroups = kr.find_all_subgroups()
        orders = sorted([s["order"] for s in subgroups])
        self.assertEqual(orders, [1, 3])


class TestSubgroupChecker(unittest.TestCase):
    """Tests for SubgroupChecker: is_normal, coset_decomposition, lattice"""

    def test_is_normal_z3_in_s3(self):
        """Z3 is normal in S3 (index 2 subgroup is always normal)"""
        s3 = build_s3()
        z3 = build_z3()
        self.assertTrue(SubgroupChecker.is_normal(z3, s3))

    def test_is_normal_z2_in_s3(self):
        """Z2 = {e, (1 2)} is NOT normal in S3"""
        s3 = build_s3()
        z2 = build_z2_swap12()
        self.assertFalse(SubgroupChecker.is_normal(z2, s3))

    def test_is_normal_trivial_subgroup(self):
        """Trivial subgroup {e} is always normal"""
        s3 = build_s3()
        trivial = [Permutation.create_identity(3)]
        self.assertTrue(SubgroupChecker.is_normal(trivial, s3))

    def test_is_normal_whole_group(self):
        """The whole group is always normal in itself"""
        s3 = build_s3()
        self.assertTrue(SubgroupChecker.is_normal(s3, s3))

    def test_cosets_z3_in_s3(self):
        """S3 / Z3 should have exactly 2 cosets, each of size 3"""
        s3 = build_s3()
        z3 = build_z3()
        cosets = SubgroupChecker.coset_decomposition(z3, s3)
        self.assertEqual(len(cosets), 2)
        self.assertEqual(len(cosets[0]), 3)
        self.assertEqual(len(cosets[1]), 3)
        # All 6 elements should appear exactly once
        all_elements = cosets[0] + cosets[1]
        self.assertEqual(len(all_elements), 6)
        for p in s3:
            count = sum(1 for e in all_elements if e.equals(p))
            self.assertEqual(count, 1, f"Permutation {p.mapping} appears {count} times")

    def test_cosets_z2_in_s3(self):
        """S3 / Z2 should have exactly 3 cosets, each of size 2"""
        s3 = build_s3()
        z2 = build_z2_swap12()
        cosets = SubgroupChecker.coset_decomposition(z2, s3)
        self.assertEqual(len(cosets), 3)
        for coset in cosets:
            self.assertEqual(len(coset), 2)

    def test_cosets_trivial(self):
        """Cosets of {e} in S3 should give 6 cosets of size 1"""
        s3 = build_s3()
        trivial = [Permutation.create_identity(3)]
        cosets = SubgroupChecker.coset_decomposition(trivial, s3)
        self.assertEqual(len(cosets), 6)
        for coset in cosets:
            self.assertEqual(len(coset), 1)

    def test_cosets_whole_group(self):
        """Cosets of S3 in S3 should give 1 coset of size 6"""
        s3 = build_s3()
        cosets = SubgroupChecker.coset_decomposition(s3, s3)
        self.assertEqual(len(cosets), 1)
        self.assertEqual(len(cosets[0]), 6)

    def test_lattice_s3(self):
        """S3 lattice should have 6 subgroups with proper inclusions"""
        s3 = build_s3()
        result = SubgroupChecker.lattice(s3)
        subgroups = result["subgroups"]
        orders = sorted([s["order"] for s in subgroups])
        self.assertEqual(orders, [1, 2, 2, 2, 3, 6])

    def test_lattice_z3(self):
        """Z3 lattice should have 2 subgroups: {e} and Z3"""
        z3 = build_z3()
        result = SubgroupChecker.lattice(z3)
        orders = sorted([s["order"] for s in result["subgroups"]])
        self.assertEqual(orders, [1, 3])

    def test_lattice_inclusions_s3(self):
        """S3 lattice inclusions: {e} ⊂ each Z2, {e} ⊂ Z3, all ⊂ S3"""
        s3 = build_s3()
        result = SubgroupChecker.lattice(s3)
        inclusions = result["inclusions"]
        subgroups = result["subgroups"]
        # There should be inclusion edges
        self.assertGreater(len(inclusions), 0)
        # Every inclusion [child, parent] should have child order < parent order
        for child_idx, parent_idx in inclusions:
            self.assertLess(subgroups[child_idx]["order"], subgroups[parent_idx]["order"])

    def test_lattice_z2(self):
        """Z2 lattice should have 2 subgroups: {e} and Z2"""
        z2 = build_z2_swap12()
        result = SubgroupChecker.lattice(z2)
        orders = sorted([s["order"] for s in result["subgroups"]])
        self.assertEqual(orders, [1, 2])

    def test_is_normal_all_z2_in_s3(self):
        """All three Z2 subgroups of S3 are NOT normal"""
        s3 = build_s3()
        for z2 in [build_z2_swap01(), build_z2_swap02(), build_z2_swap12()]:
            self.assertFalse(SubgroupChecker.is_normal(z2, s3))

    def test_lagrange_theorem(self):
        """Lagrange's theorem: |cosets| * |H| = |G|"""
        s3 = build_s3()
        for subgroup in [build_z3(), build_z2_swap12(), [Permutation.create_identity(3)]]:
            cosets = SubgroupChecker.coset_decomposition(subgroup, s3)
            self.assertEqual(len(cosets) * len(subgroup), len(s3))


class TestEdgeCases(unittest.TestCase):
    """Edge case tests for robustness"""

    def test_check_subgroup_empty_indices(self):
        kr = KeyRing(6)
        for p in build_s3():
            kr.add_key(p)
        result = kr.check_subgroup([])
        self.assertFalse(result["is_subgroup"])

    def test_closure_empty_indices(self):
        kr = KeyRing(6)
        for p in build_s3():
            kr.add_key(p)
        result = kr.get_subgroup_closure([])
        self.assertEqual(result, [])

    def test_find_subgroups_empty_keyring(self):
        kr = KeyRing(0)
        result = kr.find_all_subgroups()
        self.assertEqual(result, [])

    def test_single_element_identity_is_subgroup(self):
        kr = KeyRing(1)
        kr.add_key(Permutation.create_identity(3))
        result = kr.check_subgroup([0])
        self.assertTrue(result["is_subgroup"])

    def test_generate_subgroup_from_duplicate_generators(self):
        """Duplicate generators should not affect the result"""
        r = Permutation([1, 2, 0])
        sub1 = Permutation.generate_subgroup_from([r], 3)
        sub2 = Permutation.generate_subgroup_from([r, r], 3)
        self.assertEqual(len(sub1), len(sub2))


if __name__ == "__main__":
    unittest.main()
