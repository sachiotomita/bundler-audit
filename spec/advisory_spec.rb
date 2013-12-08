require 'spec_helper'
require 'bundler/audit/database'
require 'bundler/audit/advisory'

describe Bundler::Audit::Advisory do
  let(:root) { Bundler::Audit::Database::VENDORED_PATH }
  let(:gem)  { 'actionpack' }
  let(:id)   { 'OSVDB-84243' }
  let(:path) { File.join(root,'gems',gem,"#{id}.yml") }
  let(:an_unaffected_version) do
    Bundler::Audit::Advisory.
      # Parse the YAML-based advisory format into something coherent...
      load(path).
      # Retrieve the list of rules specifying what versions are NOT affected
      # by the advisory...
      unaffected_versions.
      # For all the rules, get the individual constraints out and see if we can
      # find a suitable one...
      map do |version_rule|
        version_rule.
          requirements.
          # We only want constraints where the version number specified is
          # one of the unaffected version.  I.E. we don't want ">", "<", or if
          # such a thing exists, "!=" constraints.
          select do |(constraint, gem_version)|
            ['~>', '>=', '=', '<='].include?(constraint)
          end.
          # Now, fetch just the version component, which is a Gem::Version,
          # and extract the string representation of the version.
          map do |(constraint, gem_version)|
            gem_version.version
          end
      end.
      # Now flatten out list-of-lists, and retrieve the first eligible version,
      # as frankly, anything from the list will do.
      flatten.
      first
  end

  describe "load" do
    let(:data) { YAML.load_file(path) }

    subject { described_class.load(path) }

    its(:id)          { should == id                  }
    its(:url)         { should == data['url']         }
    its(:title)       { should == data['title']       }
    its(:cvss_v2)     { should == data['cvss_v2']     }
    its(:description) { should == data['description'] }

    describe "#patched_versions" do
      subject { described_class.load(path).patched_versions }

      it "should all be Gem::Requirement objects" do
        subject.all? { |version|
          version.should be_kind_of(Gem::Requirement)
        }.should be_true
      end

      it "should parse the versions" do
        subject.map(&:to_s).should == data['patched_versions']
      end
    end
  end

  describe "#criticality" do
    context "when cvss_v2 is between 0.0 and 3.3" do
      before { subject.stub(:cvss_v2).and_return(3.3) }

      its(:criticality) { should == :low }
    end

    context "when cvss_v2 is between 3.3 and 6.6" do
      before { subject.stub(:cvss_v2).and_return(6.6) }

      its(:criticality) { should == :medium }
    end

    context "when cvss_v2 is between 6.6 and 10.0" do
      before { subject.stub(:cvss_v2).and_return(10.0) }

      its(:criticality) { should == :high }
    end
  end

  describe "#unaffected?" do
    subject { described_class.load(path) }

    context "when passed a version that matches one unaffected version" do
      let(:version) { Gem::Version.new(an_unaffected_version) }

      it "should return true" do
        subject.unaffected?(version).should be_true
      end
    end

    context "when passed a version that matches no unaffected version" do
      let(:version) { Gem::Version.new('3.0.9') }

      it "should return false" do
        subject.unaffected?(version).should be_false
      end
    end
  end

  describe "#patched?" do
    subject { described_class.load(path) }

    context "when passed a version that matches one patched version" do
      let(:version) { Gem::Version.new('3.1.11') }

      it "should return true" do
        subject.patched?(version).should be_true
      end
    end

    context "when passed a version that matches no patched version" do
      let(:version) { Gem::Version.new('2.9.0') }

      it "should return false" do
        subject.patched?(version).should be_false
      end
    end
  end

  describe "#vulnerable?" do
    subject { described_class.load(path) }

    context "when passed a version that matches one patched version" do
      let(:version) { Gem::Version.new('3.1.11') }

      it "should return false" do
        subject.vulnerable?(version).should be_false
      end
    end

    context "when passed a version that matches no patched version" do
      let(:version) { Gem::Version.new('2.9.0') }

      it "should return true" do
        subject.vulnerable?(version).should be_true
      end

      context "when unaffected_versions is not empty" do
        subject { described_class.load(path) }
     
        context "when passed a version that matches one unaffected version" do
          let(:version) { Gem::Version.new(an_unaffected_version) }

          it "should return false" do
            subject.vulnerable?(version).should be_false
          end
        end

        context "when passed a version that matches no unaffected version" do
          let(:version) { Gem::Version.new('1.2.3') }

          it "should return true" do
            subject.vulnerable?(version).should be_true
          end
        end
      end
    end
  end
end
