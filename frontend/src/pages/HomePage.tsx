import React, { useState, useEffect } from 'react';
import { projectService } from '../services/api';
import { Project } from '../types';
import ProjectCard from '../components/ProjectCard';

const HomePage: React.FC = () => {
  const [projects, setProjects] = useState<Project[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchProjects = async () => {
      try {
        const projectsData = await projectService.getAllProjects();
        setProjects(projectsData);
      } catch (err) {
        setError('無法載入項目列表');
        console.error('Error fetching projects:', err);
      } finally {
        setLoading(false);
      }
    };

    fetchProjects();
  }, []);

  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-64">
        <div className="text-lg">正在載入項目...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex justify-center items-center min-h-64">
        <div className="text-red-600 text-lg">{error}</div>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto">
      <div className="text-center mb-12">
        <h1 className="text-4xl font-bold text-gray-800 mb-4">
          透明的永續發展捐贈平台
        </h1>
        <p className="text-xl text-gray-600 max-w-3xl mx-auto">
          使用區塊鏈技術確保資金流向透明，讓每一筆捐贈都能被追蹤，支持真正有意義的永續發展項目。
        </p>
      </div>

      <div className="flex justify-between items-center mb-8">
        <h2 className="text-2xl font-bold text-gray-800">
          探索項目 ({projects.length})
        </h2>
        <div className="text-sm text-gray-600">
          所有數據來自 Sui 區塊鏈
        </div>
      </div>

      {projects.length === 0 ? (
        <div className="text-center py-16">
          <div className="text-6xl mb-4">🌱</div>
          <h3 className="text-xl font-semibold text-gray-700 mb-2">
            目前還沒有項目
          </h3>
          <p className="text-gray-600 mb-6">
            成為第一個建立永續發展項目的人！
          </p>
          <a 
            href="/create" 
            className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 transition-colors inline-block"
          >
            建立項目
          </a>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {projects.map((project) => (
            <ProjectCard key={project.id} project={project} />
          ))}
        </div>
      )}
    </div>
  );
};

export default HomePage;
