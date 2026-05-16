import XCTest
@testable import SkillsMaster

/// `AgentGroup` 的属性测试。
///
/// 通过遍历所有 `CaseIterable` 枚举 case 进行全量验证，
/// 确保分组归属、排序、元数据等属性在所有合法输入上成立。
final class AgentGroupTests: XCTestCase {

    // MARK: - Property 1: 分组归属唯一性

    // Feature: skill-detail-agent-assignment-grouping, Property 1: 分组归属唯一性
    // Validates: Requirements 1.1, 5.1, 5.5

    /// Every AgentType in allCases appears in exactly one AgentGroup.agents list.
    func testEveryAgentBelongsToExactlyOneGroup() {
        for agent in AgentType.allCases {
            let containingGroups = AgentGroup.allCases.filter { group in
                group.agents.contains(agent)
            }
            XCTAssertEqual(
                containingGroups.count, 1,
                "\(agent.rawValue) appears in \(containingGroups.count) groups: \(containingGroups.map(\.displayName)), expected exactly 1"
            )
        }
    }

    /// The total count of all agents across all groups equals AgentType.allCases.count.
    func testTotalAgentCountMatchesAllCases() {
        let totalAgentsInGroups = AgentGroup.allCases.reduce(0) { $0 + $1.agents.count }
        XCTAssertEqual(
            totalAgentsInGroups,
            AgentType.allCases.count,
            "Total agents across all groups (\(totalAgentsInGroups)) != AgentType.allCases.count (\(AgentType.allCases.count))"
        )
    }

    /// AgentGroup.group(for:) returns the correct group for each agent.
    func testGroupForReturnsCorrectGroup() {
        for agent in AgentType.allCases {
            let group = AgentGroup.group(for: agent)
            XCTAssertTrue(
                group.agents.contains(agent),
                "AgentGroup.group(for: .\(agent.rawValue)) returned .\(group.displayName), but that group's agents list does not contain .\(agent.rawValue)"
            )
        }
    }

    // MARK: - Property 2: 分组内排序正确性

    // Feature: skill-detail-agent-assignment-grouping, Property 2: 分组内排序正确性
    // Validates: Requirements 1.3

    /// For each AgentGroup, sortedAgents is correctly ordered:
    /// displayName.count ascending, then localizedStandardCompare ascending for ties.
    func testSortedAgentsOrderIsCorrect() {
        for group in AgentGroup.allCases {
            let sorted = group.sortedAgents

            // sortedAgents must contain the same elements as agents
            XCTAssertEqual(
                Set(sorted), Set(group.agents),
                "sortedAgents for \(group.displayName) does not contain the same elements as agents"
            )

            // Verify ordering invariant for adjacent pairs
            for i in 0..<(sorted.count - 1) {
                let current = sorted[i]
                let next = sorted[i + 1]

                let currentLen = current.displayName.count
                let nextLen = next.displayName.count

                if currentLen != nextLen {
                    XCTAssertLessThan(
                        currentLen, nextLen,
                        "In group \(group.displayName): '\(current.displayName)' (len \(currentLen)) should come before '\(next.displayName)' (len \(nextLen)) by length"
                    )
                } else {
                    // Same length: localizedStandardCompare should be ascending
                    let comparison = current.displayName.localizedStandardCompare(next.displayName)
                    XCTAssertEqual(
                        comparison, .orderedAscending,
                        "In group \(group.displayName): '\(current.displayName)' and '\(next.displayName)' have same length but are not in localizedStandardCompare ascending order"
                    )
                }
            }
        }
    }

    // MARK: - Property 7: 分组元数据完整性

    // Feature: skill-detail-agent-assignment-grouping, Property 7: 分组元数据完整性
    // Validates: Requirements 5.3, 5.4

    /// Every AgentGroup has a non-empty displayName.
    func testEveryGroupHasNonEmptyDisplayName() {
        for group in AgentGroup.allCases {
            XCTAssertFalse(
                group.displayName.isEmpty,
                "AgentGroup with rawValue \(group.rawValue) has an empty displayName"
            )
        }
    }

    /// Every AgentGroup has a unique rawValue (no duplicates).
    func testEveryGroupHasUniqueRawValue() {
        let rawValues = AgentGroup.allCases.map(\.rawValue)
        let uniqueRawValues = Set(rawValues)
        XCTAssertEqual(
            rawValues.count, uniqueRawValues.count,
            "AgentGroup rawValues contain duplicates: \(rawValues)"
        )
    }

    /// agents array is non-empty for each group.
    func testEveryGroupHasAtLeastOneAgent() {
        for group in AgentGroup.allCases {
            XCTAssertFalse(
                group.agents.isEmpty,
                "AgentGroup.\(group.displayName) has an empty agents array"
            )
        }
    }
}
